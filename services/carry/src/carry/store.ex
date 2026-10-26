# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       carry
# Module:          Carry.Store
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         The Mnesia database of the service: schema on disk,
#                  versioned migrations, the propagation log (idempotency of
#                  retried calls) and its retention.
# Related Docs:    services/carry/README.md (Database), migrations/,
#                  services/carry/docs/DATA_CLASSIFICATION.md, ADR-0032

defmodule Carry.Store do
  @moduledoc """
  The Mnesia database of the carry service.

  **Description:** Mnesia runs inside the service's BEAM node (not
  distributed, node `nonode@nohost`), with its schema and tables in
  `AAAS_DB_DIR`. `open/2` creates the disc schema on first start, starts
  Mnesia and applies the migration files `NNNN_*.json` of
  `AAAS_MIGRATIONS_DIR` in name order, each once; applied migrations are
  recorded in the table `carry_migrations` (created by the runner). A
  migration lists operations; the only one so far is `createTable`, whose
  `documentation` object is stored as the table's user property
  `aaas_documentation`, the Mnesia counterpart of `COMMENT ON`.

  The table `carry_propagations` holds one record per call, keyed by
  `{task_id, digits, position}`. `record/1` inserts a record unless one
  with the key exists, in one transaction, and returns the stored one, so
  a retried call answers the stored result and republishes the stored
  event. `prune/1` deletes records older than a cut-off.

  **Business Justification:** every service owns its database (`CLAUDE.md`
  1, rule 4), and the log makes a retried call safe: it never produces a
  second event with a new `eventId`.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **See Also:** `Carry.Propagation`, `Carry.Retention`,
  `migrations/0001_propagations.json`.
  """

  require Logger

  # The table of the propagation log.
  @table :carry_propagations

  # The attributes of the propagation log in record order; open/2 refuses
  # a database whose table has other attributes.
  @attributes [
    :key,
    :task_id,
    :digits,
    :position,
    :result,
    :event_id,
    :event,
    :propagated_at,
    :trace_id
  ]

  # The table of applied migrations, created by the runner.
  @migrations_table :carry_migrations

  # Milliseconds to wait for the tables to load at start-up.
  @load_timeout 10_000

  @typedoc """
  One propagation record: `task_id`, `digits`, `position`, `result`,
  `event_id`, `event` (JSON text), `propagated_at` (Unix milliseconds) and
  `trace_id`.
  """
  @type entry :: %{
          task_id: String.t(),
          digits: [0..9],
          position: non_neg_integer(),
          result: [0..9],
          event_id: String.t(),
          event: String.t(),
          propagated_at: integer(),
          trace_id: String.t()
        }

  @doc """
  Opens the database: schema, start of Mnesia and migrations.

  **Description:** stops Mnesia if it runs (the release loads it without
  starting it, `mix test` starts it with the default directory), points
  it at `dir`, creates the disc schema when missing, starts it and waits
  for the tables, then applies the pending migrations and checks the
  attributes of `carry_propagations`.

  **Parameters:**
  - `dir` — `String.t()`; `AAAS_DB_DIR`, created when missing.
  - `migrations_dir` — `String.t()`; `AAAS_MIGRATIONS_DIR`.

  **Returns:** `{:ok, applied}` with the number of migrations applied now,
  or `{:error, message}`.

  **Errors:** `{:error, message}` for an unreadable directory, a
  malformed migration, a failed Mnesia operation or a propagation table
  with other attributes.

  **Side Effects:** writes the Mnesia schema and tables in `dir`; starts
  the `:mnesia` application; logs every applied migration.

  **Complexity:** O(m + t) for m migration files and t tables loaded.

  **Thread Safety:** call once at start-up, before any request.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** migrations run at start-up (`CLAUDE.md`
  6.1), and the service refuses to run on a database it does not
  understand.

  **Example:** `Carry.Store.open("/data/mnesia", "/app/migrations")`
  returns `{:ok, 1}` on the first start and `{:ok, 0}` afterwards.

  **See Also:** `record/1`.
  """
  @spec open(String.t(), String.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def open(dir, migrations_dir) do
    with {:ok, files} <- migration_files(migrations_dir),
         :ok <- start_mnesia(dir),
         :ok <- ensure_migrations_table(),
         {:ok, applied} <- migrate(files, migrations_dir),
         :ok <- check_attributes() do
      {:ok, applied}
    end
  end

  @doc """
  Reads the record of a call.

  **Parameters:**
  - `key` — `{task_id, digits, position}`.

  **Returns:** `{:ok, entry}`, `:none`, or `{:error, reason}` when Mnesia
  cannot be read.

  **Errors:** none (failures are return values).

  **Side Effects:** reads the table (dirty read: records are immutable).

  **Complexity:** O(1) expected (dets hash table).

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** a retried call is answered without asking
  the digit services again.

  **Example:** `Carry.Store.lookup({task_id, [0, 9], 1})` returns `:none`
  for a new call.

  **See Also:** `record/1`.
  """
  @spec lookup({String.t(), [0..9], non_neg_integer()}) :: {:ok, entry()} | :none | {:error, term()}
  def lookup(key) do
    case :mnesia.dirty_read(@table, key) do
      [record] -> {:ok, from_record(record)}
      [] -> :none
    end
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Records a call unless a record with its key exists.

  **Parameters:**
  - `entry` — `t:entry/0`; the computed call.

  **Returns:** `{:ok, :created, entry}` when it was written,
  `{:ok, :existing, stored}` when a concurrent or earlier attempt of the
  same call was recorded first, or `{:error, reason}`.

  **Errors:** none (failures are return values).

  **Side Effects:** one Mnesia transaction (read and write of one record).

  **Complexity:** O(1) expected.

  **Thread Safety:** safe for concurrent use: the transaction locks the
  key, so two attempts of one call store one record.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** at most one event per call reaches the
  audit trail, whatever the number of retries.

  **Example:** `Carry.Store.record(entry)` returns `{:ok, :created, entry}`
  the first time.

  **See Also:** `lookup/1`, `Carry.Propagation.run/2`.
  """
  @spec record(entry()) :: {:ok, :created | :existing, entry()} | {:error, term()}
  def record(entry) do
    key = {entry.task_id, entry.digits, entry.position}

    transaction =
      :mnesia.transaction(fn ->
        case :mnesia.read(@table, key, :write) do
          [record] ->
            {:existing, from_record(record)}

          [] ->
            :ok = :mnesia.write(to_record(entry))
            {:created, entry}
        end
      end)

    case transaction do
      {:atomic, {status, stored}} -> {:ok, status, stored}
      {:aborted, reason} -> {:error, reason}
    end
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Deletes the records recorded before a cut-off.

  **Parameters:**
  - `cutoff` — integer; Unix time in milliseconds.

  **Returns:** `{:ok, deleted}` with the number of deleted records, or
  `{:error, reason}`.

  **Errors:** none (failures are return values).

  **Side Effects:** scans the table and deletes records (dirty
  operations: the deleted records belong to finished additions).

  **Complexity:** O(n) for n records.

  **Thread Safety:** safe for concurrent use with `record/1`: a record is
  older than the cut-off only long after its task ended.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the log grows with every carry; the
  retention keeps it bounded (`docs/CAPACITY.md`).

  **Example:** `Carry.Store.prune(now - 24 * 3_600_000)`.

  **See Also:** `Carry.Retention`.
  """
  @spec prune(integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def prune(cutoff) do
    pattern = List.to_tuple([@table | Enum.map(@attributes, &match_variable/1)])
    keys = :mnesia.dirty_select(@table, [{pattern, [{:<, :"$2", cutoff}], [:"$1"]}])
    Enum.each(keys, &:mnesia.dirty_delete(@table, &1))
    {:ok, length(keys)}
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Checks that the propagation log can be read.

  **Parameters:** none.

  **Returns:** `:ok`, or `{:error, reason}`.

  **Errors:** none.

  **Side Effects:** reads the table's size.

  **Complexity:** O(1).

  **Thread Safety:** safe for concurrent use.

  **Owner:** Arithmetic Excellence Center (AEC)

  **Since:** carry 0.1.0

  **Business Justification:** the `database` check of `GET /health`.

  **Example:** `Carry.Store.health()` returns `:ok` while Mnesia runs.

  **See Also:** `Carry.Http`.
  """
  @spec health() :: :ok | {:error, term()}
  def health do
    case :mnesia.table_info(@table, :size) do
      size when is_integer(size) -> :ok
    end
  catch
    :exit, reason -> {:error, reason}
  end

  # The migration files of a directory, in name order.
  #
  # Parameters:
  #   - dir: String.t(); the migrations directory.
  #
  # Returns: {:ok, [file name]} or {:error, message}.
  #
  # Errors: none. Side Effects: lists the directory.
  # Complexity: O(f log f). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: migration_files("/app/migrations") returns
  # {:ok, ["0001_propagations.json"]}.
  defp migration_files(dir) do
    case File.ls(dir) do
      {:ok, names} -> {:ok, names |> Enum.filter(&(&1 =~ ~r/\A\d{4}_.+\.json\z/)) |> Enum.sort()}
      {:error, reason} -> {:error, "cannot read the migrations directory #{dir}: #{reason}"}
    end
  end

  # Starts Mnesia on the disc schema in a directory.
  #
  # Parameters:
  #   - dir: String.t(); the Mnesia directory.
  #
  # Returns: :ok or {:error, message}.
  #
  # Errors: none. Side Effects: stops and starts :mnesia; creates the
  # directory and the schema when missing. Complexity: O(t) tables.
  # Thread Safety: start-up only. Owner: Arithmetic Excellence Center
  # (AEC). Since: carry 0.1.0.
  #
  # Example: start_mnesia("/data/mnesia") returns :ok.
  defp start_mnesia(dir) do
    :stopped = :mnesia.stop()
    Application.put_env(:mnesia, :dir, String.to_charlist(dir))

    with :ok <- mkdir(dir),
         :ok <- create_schema(),
         :ok <- :mnesia.start(),
         :ok <- :mnesia.wait_for_tables(:mnesia.system_info(:local_tables), @load_timeout) do
      :ok
    else
      {:timeout, tables} -> {:error, "Mnesia tables did not load: #{inspect(tables)}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "Mnesia did not start: #{inspect(reason)}"}
    end
  end

  # Creates a directory and its parents.
  #
  # Parameters:
  #   - dir: String.t().
  #
  # Returns: :ok or {:error, message}.
  #
  # Errors: none. Side Effects: creates directories.
  # Complexity: O(depth). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: mkdir("/data/mnesia") returns :ok.
  defp mkdir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, "cannot create #{dir}: #{reason}"}
    end
  end

  # Creates the disc schema of this node unless it exists.
  #
  # Parameters: none.
  #
  # Returns: :ok or {:error, message}.
  #
  # Errors: none. Side Effects: writes schema.DAT in the Mnesia directory.
  # Complexity: O(1). Thread Safety: start-up only, Mnesia stopped.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: create_schema() returns :ok on the first and later starts.
  defp create_schema do
    case :mnesia.create_schema([node()]) do
      :ok -> :ok
      {:error, {_node, {:already_exists, _}}} -> :ok
      {:error, reason} -> {:error, "cannot create the Mnesia schema: #{inspect(reason)}"}
    end
  end

  # Creates the table of applied migrations unless it exists.
  #
  # Parameters: none.
  #
  # Returns: :ok or {:error, message}.
  #
  # Errors: none. Side Effects: creates a disc_copies table with its
  # documentation. Complexity: O(1). Thread Safety: start-up only.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: ensure_migrations_table() returns :ok.
  defp ensure_migrations_table do
    documentation = %{
      "table" =>
        "carry_migrations: one record per applied migration file, written by the runner of Carry.Store.",
      "attributes" => %{
        "name" => "File name of the migration, such as 0001_propagations.json.",
        "applied_at" => "Unix time in milliseconds when it was applied.",
        "description" => "The description field of the file."
      }
    }

    create_table(
      @migrations_table,
      [:name, :applied_at, :description],
      :set,
      :disc_copies,
      documentation
    )
  end

  # Applies the migrations that are not recorded yet.
  #
  # Parameters:
  #   - files: [String.t()]; migration file names in order.
  #   - dir: String.t(); their directory.
  #
  # Returns: {:ok, applied count} or {:error, message}.
  #
  # Errors: none. Side Effects: Mnesia schema changes and records; a log
  # line per applied migration. Complexity: O(m).
  # Thread Safety: start-up only. Owner: Arithmetic Excellence Center
  # (AEC). Since: carry 0.1.0.
  #
  # Example: migrate(["0001_propagations.json"], dir) returns {:ok, 1}
  # on a new database.
  defp migrate(files, dir) do
    files
    |> Enum.filter(&(:mnesia.dirty_read(@migrations_table, &1) == []))
    |> Enum.reduce_while({:ok, 0}, fn file, {:ok, applied} ->
      case apply_migration(file, Path.join(dir, file)) do
        :ok -> {:cont, {:ok, applied + 1}}
        {:error, message} -> {:halt, {:error, "migration #{file}: #{message}"}}
      end
    end)
  end

  # Applies one migration file and records it.
  #
  # Parameters:
  #   - name: String.t(); the file name.
  #   - path: String.t(); its path.
  #
  # Returns: :ok or {:error, message}.
  #
  # Errors: none. Side Effects: Mnesia schema changes, one record in
  # carry_migrations, an info log line. Complexity: O(operations).
  # Thread Safety: start-up only. Owner: Arithmetic Excellence Center
  # (AEC). Since: carry 0.1.0.
  #
  # Example: apply_migration("0001_propagations.json", path) returns :ok.
  defp apply_migration(name, path) do
    with {:ok, text} <- File.read(path),
         {:ok, %{"description" => description, "operations" => operations}} <- JSON.decode(text),
         :ok <- run_operations(operations),
         :ok <-
           :mnesia.dirty_write(
             {@migrations_table, name, System.system_time(:millisecond), description}
           ) do
      Logger.info("migration applied", fields: [migration: name])
      :ok
    else
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, inspect(reason)}
      {:ok, _other} -> {:error, "a migration needs a description and operations"}
    end
  end

  # Runs the operations of a migration in order.
  #
  # Parameters:
  #   - operations: list of maps decoded from the migration file.
  #
  # Returns: :ok or {:error, message} for the first failing operation.
  #
  # Errors: none. Side Effects: Mnesia schema changes.
  # Complexity: O(operations). Thread Safety: start-up only.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: run_operations([%{"createTable" => spec}]) returns :ok.
  defp run_operations(operations) do
    Enum.reduce_while(operations, :ok, fn
      %{"createTable" => %{"name" => name, "attributes" => attributes} = spec}, :ok ->
        result =
          create_table(
            String.to_atom(name),
            Enum.map(attributes, &String.to_atom/1),
            String.to_atom(Map.get(spec, "type", "set")),
            String.to_atom(Map.get(spec, "storage", "disc_copies")),
            Map.get(spec, "documentation", %{})
          )

        if result == :ok, do: {:cont, :ok}, else: {:halt, result}

      operation, :ok ->
        {:halt, {:error, "unknown operation #{inspect(operation)}"}}
    end)
  end

  # Creates a table unless it exists.
  #
  # Parameters:
  #   - name: atom; the table (also its record name).
  #   - attributes: [atom]; the record attributes, key first.
  #   - type: :set, :ordered_set or :bag.
  #   - storage: :disc_copies or :disc_only_copies.
  #   - documentation: map stored as the user property aaas_documentation.
  #
  # Returns: :ok or {:error, message}.
  #
  # Errors: none. Side Effects: one Mnesia schema transaction.
  # Complexity: O(1). Thread Safety: start-up only.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: create_table(:t, [:k, :v], :set, :disc_copies, %{}) returns
  # :ok.
  defp create_table(name, attributes, type, storage, documentation) do
    options = [
      {:attributes, attributes},
      {:type, type},
      {storage, [node()]},
      {:user_properties, [{:aaas_documentation, documentation}]}
    ]

    case :mnesia.create_table(name, options) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^name}} -> :ok
      {:aborted, reason} -> {:error, "cannot create table #{name}: #{inspect(reason)}"}
    end
  end

  # Checks the attributes of the propagation log against the code.
  #
  # Parameters: none.
  #
  # Returns: :ok or {:error, message}.
  #
  # Errors: none. Side Effects: reads the table definition.
  # Complexity: O(1). Thread Safety: safe.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: check_attributes() returns :ok after migration 0001.
  defp check_attributes do
    case :mnesia.table_info(@table, :attributes) do
      @attributes ->
        :ok

      other ->
        {:error,
         "table #{@table} has the attributes #{inspect(other)}, expected #{inspect(@attributes)}"}
    end
  catch
    :exit, _ -> {:error, "table #{@table} does not exist; no migration created it"}
  end

  # The Mnesia record of an entry.
  #
  # Parameters:
  #   - entry: entry().
  #
  # Returns: tuple; the record in the order of @attributes.
  #
  # Errors: KeyError for a missing field. Side Effects: none.
  # Complexity: O(1). Thread Safety: pure.
  # Owner: Arithmetic Excellence Center (AEC). Since: carry 0.1.0.
  #
  # Example: to_record(entry) returns {:carry_propagations, key, ...}.
  defp to_record(entry) do
    key = {entry.task_id, entry.digits, entry.position}
    values = Enum.map(tl(@attributes), &Map.fetch!(entry, &1))
    List.to_tuple([@table, key | values])
  end

  # The entry of a Mnesia record.
  #
  # Parameters:
  #   - record: tuple; a record of carry_propagations.
  #
  # Returns: entry().
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: from_record(to_record(entry)) == entry.
  defp from_record(record) do
    [@table, _key | values] = Tuple.to_list(record)
    tl(@attributes) |> Enum.zip(values) |> Map.new()
  end

  # The match-specification variable of an attribute for prune/1: $1 for
  # the key, $2 for propagated_at, _ for the others.
  #
  # Parameters:
  #   - attribute: atom.
  #
  # Returns: atom.
  #
  # Errors: none. Side Effects: none. Complexity: O(1).
  # Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
  # Since: carry 0.1.0.
  #
  # Example: match_variable(:key) returns :"$1".
  defp match_variable(:key), do: :"$1"
  defp match_variable(:propagated_at), do: :"$2"
  defp match_variable(_attribute), do: :_
end
