! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/http.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         A minimal HTTP/1.1 server in Fortran over POSIX sockets:
!                  one connection at a time, one request per connection,
!                  graceful stop on SIGTERM.
! Related Docs:    services/digit-2/README.md, ADR-0024, CLAUDE.md 4.4

!> Minimal HTTP/1.1 server (one request per connection).
!>
!> **Description:** Accepts a connection, reads the request line and the
!> headers (at most 8 KiB within 500 ms), passes method, path and
!> `traceparent` to the handler, writes the reply with
!> `Connection: close`, then closes the connection after a short drain of
!> any unread request body. The listening socket is polled every 200 ms so
!> that SIGTERM stops the loop promptly.
!>
!> **Business Justification:** Fortran has no HTTP server library; this
!> module keeps the request handling in Fortran instead of an external
!> wrapper (ADR-0024, CLAUDE.md 4.4).
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_posix]], [[digit_api]]
module digit_http
  use, intrinsic :: iso_c_binding, only: c_int, c_int8_t, c_long, c_size_t, c_intptr_t, c_char, c_null_ptr
  use digit_posix
  use digit_api, only: reply_t, problem
  implicit none
  private

  public :: request_handler, ready_callback, http_serve, parse_request, format_response

  !> Largest request head (request line and headers) accepted, in bytes.
  integer, parameter :: max_head_bytes = 8192
  !> Time allowed to receive the request head, in milliseconds. Callers on
  !> the `services` network send the head at once; a silent connection holds
  !> the single-threaded server for at most this long, which stays below the
  !> 2 s call timeout of CLAUDE.md 6.1.
  integer, parameter :: read_timeout_ms = 500
  !> Poll interval of the listening socket, in milliseconds.
  integer(c_int), parameter :: accept_poll_ms = 200
  !> Drain rounds after the reply, each waiting at most 50 ms.
  integer, parameter :: drain_rounds = 4
  !> Pending connections queued by the kernel.
  integer(c_int), parameter :: listen_backlog = 128
  !> Carriage return and line feed.
  character(len=2), parameter :: crlf = achar(13)//achar(10)

  !> Answer one request (the handler passed to [[http_serve]]).
  abstract interface
    subroutine request_handler(method, path, traceparent, reply)
      !! Answer one request (the handler passed to [[http_serve]]).
      import :: reply_t
      !> HTTP method as sent.
      character(len=*), intent(in) :: method
      !> Path without the query string.
      character(len=*), intent(in) :: path
      !> Value of the `traceparent` header, empty when absent.
      character(len=*), intent(in) :: traceparent
      !> The reply to send.
      type(reply_t), intent(out) :: reply
    end subroutine request_handler
  end interface

  !> Called once when the server listens.
  abstract interface
    subroutine ready_callback()
      !! Called once when the server listens.
    end subroutine ready_callback
  end interface

contains

  !> Serve HTTP on a port until SIGTERM or SIGINT.
  !>
  !> **Description:** Binds `0.0.0.0:port` with `SO_REUSEADDR`, calls
  !> `on_ready` once listening, then answers connections one at a time with
  !> `handler` until `stop_requested` is set.
  !>
  !> **Business Justification:** The HTTP endpoint of the digit contract.
  !>
  !> **Returns:** `ok` false when the port cannot be bound.
  !> **Errors:** See Returns. **Side Effects:** Network I/O.
  !>
  !> **Complexity:** O(1) per request. **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call http_serve(8080, handle, announce, ok)`
  !>
  !> **See Also:** [[request_handler]]
  subroutine http_serve(port, handler, on_ready, ok)
    !> TCP port, 1..65535.
    integer, intent(in) :: port
    !> Request handler.
    procedure(request_handler) :: handler
    !> Called once the socket listens.
    procedure(ready_callback) :: on_ready
    !> False when the server could not start.
    logical, intent(out) :: ok
    integer(c_int) :: one !! Option value 1 (enable).
    integer(c_int8_t) :: address(16) !! The `sockaddr_in` bytes: family, port (network order), any address.
    integer(c_int) :: listener !! Listening socket.
    integer(c_int) :: client !! Accepted connection.
    integer(c_int) :: rc !! Return code of the C call.
    type(pollfd) :: watch !! Descriptor passed to poll().

    one = 1
    listener = c_socket(af_inet, sock_stream, 0_c_int)
    ok = listener >= 0
    if (.not. ok) return
    rc = c_setsockopt(listener, sol_socket, so_reuseaddr, one, 4_c_int)
    address = 0_c_int8_t
    address(1) = int(af_inet, c_int8_t)
    address(3) = int(signed_byte(port/256), c_int8_t)
    address(4) = int(signed_byte(modulo(port, 256)), c_int8_t)
    ok = c_bind(listener, address, 16_c_int) == 0
    if (ok) ok = c_listen(listener, listen_backlog) == 0
    if (.not. ok) then
      rc = c_close(listener)
      return
    end if
    call on_ready()
    do while (.not. stop_requested)
      watch%fd = listener
      watch%events = pollin
      watch%revents = 0
      if (c_poll(watch, 1_c_long, accept_poll_ms) <= 0) cycle
      client = c_accept(listener, c_null_ptr, c_null_ptr)
      if (client < 0) cycle
      call serve_connection(client, handler)
    end do
    rc = c_close(listener)
  end subroutine http_serve

  !> Two's-complement value of a byte 0..255 as a signed 8-bit number.
  !>
  !> **Description:** Fortran has no unsigned integers; bytes above 127 are
  !> stored as negative `c_int8_t` values.
  !>
  !> **Business Justification:** Builds the port bytes of `sockaddr_in`.
  !>
  !> **Returns:** The value in -128..127. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `signed_byte(144)` is -112.
  !>
  !> **See Also:** [[http_serve]]
  pure function signed_byte(byte) result(value)
    !> Byte value, 0..255.
    integer, intent(in) :: byte
    !> Signed value.
    integer :: value
    value = byte
    if (value > 127) value = value - 256
  end function signed_byte

  !> Read, answer and close one connection.
  !>
  !> **Description:** A head that cannot be parsed answers 400 problem
  !> details, a head above 8 KiB 431; a peer that sends nothing is closed
  !> silently. HEAD replies carry the headers only.
  !>
  !> **Business Justification:** One request per connection keeps the
  !> single-threaded server simple and fair between callers.
  !>
  !> **Errors:** None (failures close the connection).
  !> **Side Effects:** Network I/O; calls the handler.
  !>
  !> **Complexity:** O(n) in the request size.
  !> **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call serve_connection(client, handler)`
  !>
  !> **See Also:** [[parse_request]], [[format_response]]
  subroutine serve_connection(client, handler)
    !> Connected socket; closed on return.
    integer(c_int), intent(in) :: client
    !> Request handler.
    procedure(request_handler) :: handler
    character(len=:), allocatable :: head !! Bytes of the request head.
    character(len=:), allocatable :: method !! Parsed method.
    character(len=:), allocatable :: path !! Parsed path.
    character(len=:), allocatable :: traceparent !! Parsed traceparent value.
    type(reply_t) :: reply !! Reply under test.
    logical :: complete !! Whether the head ended with an empty line.
    logical :: parsed !! Whether the request line was valid.
    integer(c_int) :: rc !! Return code of the C call.

    call read_head(client, head, complete)
    if (len(head) > 0) then
      parsed = .false.
      if (complete) call parse_request(head, method, path, traceparent, parsed)
      if (parsed) then
        call handler(method, path, traceparent, reply)
        call send_all(client, format_response(reply, method /= 'HEAD'))
      else if (len(head) >= max_head_bytes) then
        call send_all(client, format_response(problem(431, 'Request Header Fields Too Large', &
                                                      'the request head exceeds 8 KiB'), .true.))
      else
        call send_all(client, format_response(problem(400, 'Bad Request', 'the request could not be read'), &
                                              .true.))
      end if
    end if
    rc = c_shutdown(client, shut_wr)
    call drain(client)
    rc = c_close(client)
  end subroutine serve_connection

  !> Receive the request head (up to the empty line).
  !>
  !> **Description:** Reads until `CRLF CRLF`, 8 KiB, the end of the
  !> stream or 500 ms; any body bytes received with the head are kept.
  !>
  !> **Business Justification:** Bounds memory and time per request.
  !>
  !> **Returns:** `complete` true when the empty line was received.
  !> **Errors:** See Returns. **Side Effects:** Reads the socket.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call read_head(client, head, complete)`
  !>
  !> **See Also:** [[serve_connection]]
  subroutine read_head(client, head, complete)
    !> Connected socket.
    integer(c_int), intent(in) :: client
    !> Bytes received.
    character(len=:), allocatable, intent(out) :: head
    !> True when the whole head was received.
    logical, intent(out) :: complete
    character(kind=c_char, len=4096) :: chunk !! Receive buffer.
    integer(c_intptr_t) :: received !! Bytes received by the last recv().
    integer(c_long) :: deadline !! Time limit of the head, in ms since the epoch.
    integer(c_long) :: remaining !! Milliseconds left until the deadline.
    type(pollfd) :: watch !! Descriptor passed to poll().

    head = ''
    complete = .false.
    deadline = now_ms() + read_timeout_ms
    do while (len(head) < max_head_bytes)
      remaining = deadline - now_ms()
      if (remaining <= 0) return
      watch%fd = client
      watch%events = pollin
      watch%revents = 0
      if (c_poll(watch, 1_c_long, int(remaining, c_int)) <= 0) return
      received = c_recv(client, chunk, int(min(len(chunk), max_head_bytes - len(head)), c_size_t), 0_c_int)
      if (received <= 0) return
      head = head//chunk(1:received)
      if (index(head, crlf//crlf) > 0) then
        complete = .true.
        return
      end if
    end do
  end subroutine read_head

  !> Read and discard what the peer still sends, briefly.
  !>
  !> **Description:** After the reply and `shutdown(SHUT_WR)`, reads until
  !> the end of the stream or four empty 50 ms waits, so that closing does
  !> not reset a connection with an unread request body.
  !>
  !> **Business Justification:** The caller receives the whole reply even
  !> when it sent a body the contract does not use.
  !>
  !> **Errors:** None. **Side Effects:** Reads the socket.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call drain(client)`
  !>
  !> **See Also:** [[serve_connection]]
  subroutine drain(client)
    !> Connected socket.
    integer(c_int), intent(in) :: client
    character(kind=c_char, len=4096) :: chunk !! Receive buffer.
    type(pollfd) :: watch !! Descriptor passed to poll().
    integer :: idle !! Consecutive polls without data.

    idle = 0
    do while (idle < drain_rounds)
      watch%fd = client
      watch%events = pollin
      watch%revents = 0
      if (c_poll(watch, 1_c_long, 50_c_int) <= 0) then
        idle = idle + 1
        cycle
      end if
      if (c_recv(client, chunk, int(len(chunk), c_size_t), 0_c_int) <= 0) return
    end do
  end subroutine drain

  !> Send a whole string.
  !>
  !> **Description:** Repeats `send` until every byte is written or an
  !> error occurs (`MSG_NOSIGNAL`: a closed peer is not a signal).
  !>
  !> **Business Justification:** Large replies (metrics) may need several
  !> writes.
  !>
  !> **Errors:** None (a failed write abandons the reply).
  !> **Side Effects:** Writes the socket.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call send_all(client, response)`
  !>
  !> **See Also:** [[format_response]]
  subroutine send_all(client, data)
    !> Connected socket.
    integer(c_int), intent(in) :: client
    !> Bytes to send.
    character(len=*), intent(in) :: data
    integer :: sent !! Bytes sent so far.
    integer(c_intptr_t) :: n !! Bytes sent by the last send().
    sent = 0
    do while (sent < len(data))
      n = c_send(client, data(sent + 1:), int(len(data) - sent, c_size_t), msg_nosignal)
      if (n <= 0) return
      sent = sent + int(n)
    end do
  end subroutine send_all

  !> Milliseconds of the wall clock.
  !>
  !> **Description:** From `clock_gettime(CLOCK_REALTIME)`.
  !>
  !> **Business Justification:** Deadlines of the request head.
  !>
  !> **Returns:** Milliseconds since the epoch. **Errors:** None.
  !> **Side Effects:** Reads the clock.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `deadline = now_ms() + 2000`
  !>
  !> **See Also:** [[read_head]]
  function now_ms() result(ms)
    !> Milliseconds since the epoch.
    integer(c_long) :: ms
    type(timespec) :: now !! Current wall-clock time.
    integer(c_int) :: rc !! Return code of the C call.
    rc = c_clock_gettime(clock_realtime, now)
    ms = now%tv_sec*1000_c_long + now%tv_nsec/1000000_c_long
  end function now_ms

  !> Parse the request line and the `traceparent` header of a request head.
  !>
  !> **Description:** The request line must be `METHOD SP TARGET SP
  !> HTTP/1.x`; the path is the target without query (`?`) or fragment
  !> (`#`). Header names compare case-insensitively; the value of
  !> `traceparent` is stripped of surrounding blanks.
  !>
  !> **Business Justification:** The contract routes on method and path
  !> only; the trace joins the logs.
  !>
  !> **Returns:** `ok` false for a malformed request line.
  !> **Errors:** See Returns. **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call parse_request('GET /next?x=1 HTTP/1.1'//crlf//crlf, m, p, t, ok)`
  !> gives `GET` and `/next`.
  !>
  !> **See Also:** [[serve_connection]]
  pure subroutine parse_request(head, method, path, traceparent, ok)
    !> Request head including the empty line.
    character(len=*), intent(in) :: head
    !> The method.
    character(len=:), allocatable, intent(out) :: method
    !> The path without query string.
    character(len=:), allocatable, intent(out) :: path
    !> The `traceparent` value, empty when absent.
    character(len=:), allocatable, intent(out) :: traceparent
    !> True when the request line is well formed.
    logical, intent(out) :: ok
    character(len=:), allocatable :: line !! Current line of the head.
    character(len=:), allocatable :: target !! Request target.
    character(len=:), allocatable :: version !! Protocol version.
    character(len=:), allocatable :: name !! Lower-case header name.
    integer :: start !! Start of the current line.
    integer :: eol !! Position of the next CRLF.
    integer :: first !! Position of the first space or non-blank.
    integer :: second !! Position of the last space.
    integer :: colon !! Position of the header colon.
    integer :: cut !! Position of `?` or `#` in the target.

    method = ''
    path = ''
    traceparent = ''
    ok = .false.
    eol = index(head, crlf)
    if (eol <= 1) return
    line = head(1:eol - 1)
    first = index(line, ' ')
    second = index(line, ' ', back=.true.)
    if (first <= 1 .or. second <= first + 1) return
    method = line(1:first - 1)
    target = line(first + 1:second - 1)
    version = line(second + 1:)
    if (index(target, ' ') > 0 .or. target(1:1) /= '/' .or. len(version) /= 8) return
    if (version(1:7) /= 'HTTP/1.') return
    if (verify(method, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') /= 0) return
    cut = scan(target, '?#')
    if (cut > 0) then
      path = target(1:cut - 1)
    else
      path = target
    end if
    start = eol + 2
    do
      eol = index(head(start:), crlf)
      if (eol <= 1) exit
      line = head(start:start + eol - 2)
      start = start + eol + 1
      colon = index(line, ':')
      if (colon <= 1) cycle
      name = lower(line(1:colon - 1))
      if (name == 'traceparent') traceparent = strip(line(colon + 1:))
    end do
    ok = .true.
  end subroutine parse_request

  !> Lower-case the ASCII letters of a string.
  !>
  !> **Description:** Header names are case-insensitive (RFC 9110).
  !>
  !> **Business Justification:** Finds `traceparent` in any spelling.
  !>
  !> **Returns:** The lower-case text. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `lower('TraceParent')` is `traceparent`.
  !>
  !> **See Also:** [[parse_request]]
  pure function lower(text) result(converted)
    !> Text.
    character(len=*), intent(in) :: text
    !> The text with A..Z replaced by a..z.
    character(len=len(text)) :: converted
    integer :: i !! Loop index.
    converted = text
    do i = 1, len(text)
      if (converted(i:i) >= 'A' .and. converted(i:i) <= 'Z') converted(i:i) = achar(iachar(converted(i:i)) + 32)
    end do
  end function lower

  !> Remove leading and trailing blanks and tabs.
  !>
  !> **Description:** Header values may be surrounded by optional
  !> whitespace (RFC 9110).
  !>
  !> **Business Justification:** The `traceparent` value is compared by
  !> length.
  !>
  !> **Returns:** The stripped text. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `strip(' 00-ab ')` is `00-ab`.
  !>
  !> **See Also:** [[parse_request]]
  pure function strip(text) result(stripped)
    !> Text.
    character(len=*), intent(in) :: text
    !> The text without surrounding blanks and tabs.
    character(len=:), allocatable :: stripped
    integer :: first !! Position of the first space or non-blank.
    integer :: last !! Position of the last non-blank.
    first = verify(text, ' '//achar(9))
    last = verify(text, ' '//achar(9), back=.true.)
    if (first == 0) then
      stripped = ''
    else
      stripped = text(first:last)
    end if
  end function strip

  !> Serialise a reply as an HTTP/1.1 response.
  !>
  !> **Description:** Status line, `Content-Type`, `Content-Length`,
  !> `Allow` when set, `Connection: close`, then the body unless
  !> `with_body` is false (HEAD).
  !>
  !> **Business Justification:** The wire format of every answer.
  !>
  !> **Returns:** The response bytes. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `response = format_response(reply, .true.)`
  !>
  !> **See Also:** [[serve_connection]]
  function format_response(reply, with_body) result(response)
    !> The reply.
    type(reply_t), intent(in) :: reply
    !> False for HEAD.
    logical, intent(in) :: with_body
    !> The response.
    character(len=:), allocatable :: response
    character(len=12) :: number !! Formatting buffer for a number.
    write (number, '(i0)') reply%status
    response = 'HTTP/1.1 '//trim(number)//' '//reason(reply%status)//crlf// &
               'Content-Type: '//reply%content_type//crlf
    write (number, '(i0)') len(reply%body)
    response = response//'Content-Length: '//trim(number)//crlf
    if (len(reply%allow) > 0) response = response//'Allow: '//reply%allow//crlf
    response = response//'Connection: close'//crlf//crlf
    if (with_body) response = response//reply%body
  end function format_response

  !> Reason phrase of a status code.
  !>
  !> **Description:** The codes the service sends; others get an empty
  !> phrase, which HTTP/1.1 allows.
  !>
  !> **Business Justification:** Readable status lines.
  !>
  !> **Returns:** The phrase. **Errors:** None. **Side Effects:** None.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `reason(405)` is `Method Not Allowed`.
  !>
  !> **See Also:** [[format_response]]
  pure function reason(status) result(phrase)
    !> HTTP status.
    integer, intent(in) :: status
    !> The reason phrase.
    character(len=:), allocatable :: phrase
    select case (status)
    case (200)
      phrase = 'OK'
    case (400)
      phrase = 'Bad Request'
    case (404)
      phrase = 'Not Found'
    case (405)
      phrase = 'Method Not Allowed'
    case (431)
      phrase = 'Request Header Fields Too Large'
    case (503)
      phrase = 'Service Unavailable'
    case default
      phrase = ''
    end select
  end function reason

end module digit_http
