// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/main.cpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Entry point of the digit-1 service: configuration from
//                  the environment, database migrations, the HTTP server
//                  (cpp-httplib) on port 8080 and graceful shutdown.
// Related Docs:    services/digit-1/README.md, CLAUDE.md 4.4, 6.1,
//                  ADR-0022, ADR-0023

/**
 * @file main.cpp
 * @brief Process entry point: configuration, start-up and shutdown.
 *
 * @details Start-up: read the configuration (AAAS_BOOTSTRAP=env until
 * P5.2), open and migrate the database, check that it holds the configured
 * digit, then serve HTTP until SIGTERM or SIGINT. Shutdown stops the
 * server, waits for the listener thread and closes the database, well
 * within the 10 s of CLAUDE.md 6.1.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#include <charconv>
#include <csignal>
#include <cstdlib>
#include <format>
#include <httplib.h>
#include <optional>
#include <string>
#include <string_view>
#include <thread>

#include "api.hpp"
#include "log.hpp"
#include "metrics.hpp"
#include "store.hpp"
#include "trace.hpp"

namespace {

using namespace aaas::digit;

/// @brief Version of the service (SemVer, docs/CHANGELOG.md).
constexpr std::string_view service_version = "0.1.0";

/// @brief Seconds after which an idle keep-alive connection is closed.
constexpr time_t keep_alive_timeout_s = 10;

/// @brief Worker threads of the HTTP server (requests share one database
///        connection under a mutex, so more threads would only wait).
constexpr std::size_t worker_threads = 4;

/// @brief Largest request body accepted, in bytes; the contract has none,
///        larger bodies answer 413.
constexpr std::size_t max_body_bytes = 1024;

/**
 * @brief Configuration of the process, from the environment.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @see load_config
 */
struct Config {
  std::string db_path;        ///< AAAS_DB_PATH (default `/data/digit-1.db`).
  std::string migrations_dir; ///< AAAS_MIGRATIONS_DIR (default `/app/migrations`).
  int digit = 1;              ///< AAAS_DIGIT, 0..9 (default 1).
  int port = 8080;            ///< AAAS_HTTP_PORT (default 8080).
};

/**
 * @brief Value of an environment variable, or std::nullopt when unset or
 *        empty.
 *
 * @details Thin wrapper over std::getenv.
 *
 * @par Business Justification
 * Configuration comes only from the environment (CLAUDE.md 6.1).
 *
 * @param name Variable name.
 * @return The value, or std::nullopt.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Reads the environment.
 * @par Complexity
 * O(e) in the size of the environment.
 * @par Thread Safety
 * Safe while no thread modifies the environment.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * std::string path = env("AAAS_DB_PATH").value_or("/data/digit-1.db");
 * @endcode
 * @see load_config
 */
std::optional<std::string> env(const char *name) {
  const char *value = std::getenv(name); // NOLINT(concurrency-mt-unsafe): read before any thread starts
  if (value == nullptr || *value == '\0') {
    return std::nullopt;
  }
  return std::string(value);
}

/**
 * @brief Parse a decimal integer in [min, max].
 *
 * @details The whole string must be the number.
 *
 * @par Business Justification
 * Rejects misconfiguration (for example a port of 0) at start-up.
 *
 * @param text Text to parse.
 * @param min Smallest accepted value.
 * @param max Largest accepted value.
 * @return The value, or std::nullopt for non-numeric text or a value out of
 *         range.
 *
 * @par Errors
 * None (std::nullopt).
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the text length.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * auto port = parse_int("8080", 1, 65535); // 8080
 * @endcode
 * @see load_config
 */
std::optional<int> parse_int(std::string_view text, int min, int max) {
  int value = 0;
  const auto [end, ec] = std::from_chars(text.data(), text.data() + text.size(), value);
  if (ec != std::errc{} || end != text.data() + text.size() || value < min || value > max) {
    return std::nullopt;
  }
  return value;
}

/**
 * @brief Read the configuration from the environment.
 *
 * @details Only AAAS_BOOTSTRAP=env is available until the config server and
 * OpenBao exist (P5.2, P5.3); `platform` is refused.
 *
 * @par Business Justification
 * CLAUDE.md 3 ("Platform at the start of every service") and 6.1.
 *
 * @return The configuration, or std::nullopt when it is invalid (logged).
 *
 * @par Errors
 * std::nullopt for AAAS_BOOTSTRAP other than `env`, or an invalid
 * AAAS_DIGIT or AAAS_HTTP_PORT.
 * @par Side Effects
 * Reads the environment; logs errors.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Not safe; call once at start-up.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * auto cfg = load_config();
 * if (!cfg) return 1;
 * @endcode
 * @see main
 */
std::optional<Config> load_config() {
  const std::string bootstrap = env("AAAS_BOOTSTRAP").value_or("env");
  if (bootstrap != "env") {
    logging::write(logging::Level::error, "unsupported AAAS_BOOTSTRAP; only env exists before P5.2", std::nullopt,
                   bootstrap);
    return std::nullopt;
  }
  const std::string digit_text = env("AAAS_DIGIT").value_or("1");
  const auto digit = parse_int(digit_text, 0, 9);
  if (!digit) {
    logging::write(logging::Level::error, "AAAS_DIGIT must be 0..9", std::nullopt, digit_text);
    return std::nullopt;
  }
  const std::string port_text = env("AAAS_HTTP_PORT").value_or("8080");
  const auto port = parse_int(port_text, 1, 65535); // NOLINT(readability-magic-numbers): TCP port range
  if (!port) {
    logging::write(logging::Level::error, "AAAS_HTTP_PORT must be 1..65535", std::nullopt, port_text);
    return std::nullopt;
  }
  return Config{
      .db_path = env("AAAS_DB_PATH").value_or("/data/digit-1.db"),
      .migrations_dir = env("AAAS_MIGRATIONS_DIR").value_or("/app/migrations"),
      .digit = *digit,
      .port = *port,
  };
}

/**
 * @brief Copy a contract reply into an httplib response.
 *
 * @details Sets the status, the body with its Content-Type and, for 405,
 * the Allow header.
 *
 * @par Business Justification
 * Keeps the server library out of the contract code (src/api.cpp).
 *
 * @param reply Reply from Api::handle() or problem().
 * @param[out] res Response to fill.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the body length.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * send(api.handle(req.method, req.path), res);
 * @endcode
 * @see configure
 */
void send(Reply reply, httplib::Response &res) {
  res.status = reply.status;
  if (reply.allow) {
    res.set_header("Allow", *reply.allow);
  }
  res.set_content(std::move(reply.body), reply.content_type);
}

/**
 * @brief Configure the HTTP server to answer every request through Api.
 *
 * @details One catch-all route per method that httplib routes (GET, HEAD
 * through GET, POST, PUT, PATCH, DELETE, OPTIONS) sends the request to
 * Api::handle(), so that 404 and 405 are the contract's problem details.
 * Routes, unlike a pre-routing handler, run after httplib has read the
 * request body, so a body never stays on a keep-alive connection to be
 * misread as the next request. Errors that httplib produces itself arrive
 * with an empty body: TRACE and CONNECT, which it parses but cannot route
 * (400), are answered through Api::handle() as well (405 or 404); a body
 * above 1 KiB (413) and a malformed request, including a method name
 * outside HTTP (400), become problem details with httplib's status. The logger writes one debug line
 * per request, with the caller's trace when the `traceparent` header is
 * valid. TCP_NODELAY is on, so that keep-alive calls are not delayed.
 *
 * @par Business Justification
 * Bridges the server library to the library-independent contract code.
 *
 * @param server Server to configure.
 * @param api Contract implementation; must outlive the server.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Registers handlers on @p server.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Not safe; call before listening.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * httplib::Server server;
 * configure(server, api);
 * @endcode
 * @see Api::handle, send
 */
void configure(httplib::Server &server, Api &api) {
  // NOLINTNEXTLINE(cppcoreguidelines-owning-memory): the server takes ownership of the queue
  server.new_task_queue = [] { return new httplib::ThreadPool(worker_threads); };
  server.set_keep_alive_timeout(keep_alive_timeout_s);
  // Headers and body leave in separate writes; without TCP_NODELAY, Nagle's
  // algorithm and the client's delayed ACK add about 40 ms to every
  // keep-alive call (measured in P2.4).
  server.set_tcp_nodelay(true);
  server.set_payload_max_length(max_body_bytes);
  const auto answer = [&api](const httplib::Request &req, httplib::Response &res) {
    send(api.handle(req.method, req.path), res);
  };
  const std::string any_path = ".*";
  server.Get(any_path, answer);
  server.Post(any_path, answer);
  server.Put(any_path, answer);
  server.Patch(any_path, answer);
  server.Delete(any_path, answer);
  server.Options(any_path, answer);
  server.set_error_handler([&api](const httplib::Request &req, httplib::Response &res) {
    if (!res.body.empty()) {
      return httplib::Server::HandlerResponse::Unhandled; // a contract reply
    }
    if (req.method == "TRACE" || req.method == "CONNECT") {
      send(api.handle(req.method, req.path), res); // valid methods without a route: 405 or 404
    } else {
      send(problem(res.status, httplib::status_message(res.status), "the HTTP server rejected the request"), res);
    }
    return httplib::Server::HandlerResponse::Handled;
  });
  server.set_logger([](const httplib::Request &req, const httplib::Response &res) {
    logging::write(logging::Level::debug, "request answered", parse_traceparent(req.get_header_value("traceparent")),
                   std::format("{} {} -> {}", req.method, req.path, res.status));
  });
}

} // namespace

/**
 * @brief Run the service.
 *
 * @details See the file documentation. SIGTERM and SIGINT are blocked
 * before any thread starts, so that only this thread receives them through
 * sigwait().
 *
 * @par Business Justification
 * Digit 1 as a service (CLAUDE.md 2, row 14).
 *
 * @return 0 after a clean shutdown, 1 when start-up fails.
 *
 * @par Errors
 * 1 for invalid configuration, an unopenable or unmigratable database, a
 * database holding another digit, or a port that cannot be bound.
 * @par Side Effects
 * Opens the database, binds the port, writes logs.
 * @par Complexity
 * Not applicable.
 * @par Thread Safety
 * Not applicable (process entry point).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * AAAS_DB_PATH=/tmp/d.db AAAS_MIGRATIONS_DIR=migrations ./digit-1
 * @endcode
 * @see load_config, configure
 */
int main() {
  logging::init(env("AAAS_SERVICE").value_or("digit-1"),
                logging::parse_level(env("AAAS_LOG_LEVEL"), logging::Level::info));
  const auto cfg = load_config();
  if (!cfg) {
    return 1;
  }
  try {
    Store store(cfg->db_path);
    store.migrate(cfg->migrations_dir);
    if (store.read().digit != cfg->digit) {
      logging::write(logging::Level::error, "the database does not hold the configured digit", std::nullopt,
                     cfg->db_path);
      return 1;
    }
    Metrics metrics(cfg->digit, std::string(service_version));
    Api api(store, cfg->digit, metrics);

    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGTERM);
    sigaddset(&signals, SIGINT);
    pthread_sigmask(SIG_BLOCK, &signals, nullptr);

    httplib::Server server;
    configure(server, api);
    if (!server.bind_to_port("0.0.0.0", cfg->port)) {
      logging::write(logging::Level::error, "cannot start the HTTP server", std::nullopt,
                     std::format("port {}", cfg->port));
      return 1;
    }
    std::thread listener([&server] { server.listen_after_bind(); });
    server.wait_until_ready();
    logging::write(logging::Level::info, "listening", std::nullopt,
                   std::format("port {}, digit {}, version {}", cfg->port, cfg->digit, service_version));

    int received = 0;
    sigwait(&signals, &received);
    logging::write(logging::Level::info, "shutting down", std::nullopt, received == SIGTERM ? "SIGTERM" : "SIGINT");
    server.stop();
    listener.join();
  } catch (const StoreError &error) {
    logging::write(logging::Level::error, "the database cannot be prepared", std::nullopt, error.what());
    return 1;
  }
  logging::write(logging::Level::info, "stopped", std::nullopt, std::nullopt);
  return 0;
}
