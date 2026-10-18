! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/posix.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         Fortran interfaces to the POSIX calls the service needs
!                  (sockets, poll, signals, clock, directories, exit) and
!                  conversions between Fortran and C strings.
! Related Docs:    services/digit-2/README.md, ADR-0024

!> POSIX interfaces of the digit-2 service (ISO_C_BINDING).
!>
!> **Description:** Fortran has no standard sockets, signals, clock with
!> milliseconds or directory listing, so the service calls the C library
!> directly through `bind(C)` interfaces; no C code is compiled. Constants
!> are the Linux values (identical on amd64 and arm64).
!>
!> **Business Justification:** Lets the whole HTTP server and the digit
!> logic stay in Fortran, without an HTTP wrapper (ADR-0024).
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_http]], ADR-0024
module digit_posix
  use, intrinsic :: iso_c_binding, only: c_char, c_int, c_short, c_long, c_size_t, c_intptr_t, c_int8_t
  use, intrinsic :: iso_c_binding, only: c_ptr, c_funptr, c_null_char, c_associated, c_f_pointer, c_funloc
  implicit none
  private

  public :: af_inet, sock_stream, sol_socket, so_reuseaddr, pollin, msg_nosignal, shut_wr
  public :: pollfd, timespec
  public :: c_socket, c_setsockopt, c_bind, c_listen, c_accept, c_recv, c_send, c_close, c_shutdown, c_poll
  public :: c_clock_gettime, c_exit
  public :: to_c_string, from_c_string, list_directory
  public :: install_stop_handlers, stop_requested, stop_signal

  !> Address family IPv4 (`AF_INET`).
  integer(c_int), parameter :: af_inet = 2
  !> Stream socket type (`SOCK_STREAM`).
  integer(c_int), parameter :: sock_stream = 1
  !> Socket option level (`SOL_SOCKET`).
  integer(c_int), parameter :: sol_socket = 1
  !> Option allowing a quick rebind after a restart (`SO_REUSEADDR`).
  integer(c_int), parameter :: so_reuseaddr = 2
  !> Poll event: data to read (`POLLIN`).
  integer(c_short), parameter :: pollin = 1_c_short
  !> Send flag suppressing SIGPIPE on a closed peer (`MSG_NOSIGNAL`).
  integer(c_int), parameter :: msg_nosignal = 16384
  !> Shutdown direction: no more writes (`SHUT_WR`).
  integer(c_int), parameter :: shut_wr = 1
  !> Signal number of `SIGINT`.
  integer(c_int), parameter :: sigint = 2
  !> Signal number of `SIGTERM`.
  integer(c_int), parameter :: sigterm = 15
  !> Clock id of the wall clock (`CLOCK_REALTIME`).
  integer(c_int), parameter, public :: clock_realtime = 0
  !> Byte offset of `d_name` in `struct dirent` (musl and glibc, 64-bit Linux:
  !> `d_ino` 8, `d_off` 8, `d_reclen` 2, `d_type` 1).
  integer, parameter :: dirent_name_offset = 19
  !> Capacity of `d_name` in bytes, including the terminating NUL.
  integer, parameter :: dirent_name_capacity = 256

  !> One entry of the `poll()` array (`struct pollfd`).
  type, bind(C) :: pollfd
    !> File descriptor to watch.
    integer(c_int) :: fd = -1
    !> Requested events.
    integer(c_short) :: events = 0_c_short
    !> Returned events.
    integer(c_short) :: revents = 0_c_short
  end type pollfd

  !> A point in time (`struct timespec`; `time_t` is 64-bit).
  type, bind(C) :: timespec
    !> Seconds since the epoch.
    integer(c_long) :: tv_sec = 0
    !> Nanoseconds, 0..999 999 999.
    integer(c_long) :: tv_nsec = 0
  end type timespec

  !> True once SIGTERM or SIGINT has been received.
  logical, volatile :: stop_requested = .false.
  !> Number of the signal that requested the stop, 0 before.
  integer(c_int), volatile :: stop_signal = 0

  !> `socket(2)`: create an endpoint; returns the descriptor or -1.
  interface
    function c_socket(domain, type, protocol) bind(C, name='socket') result(fd)
      !! `socket(2)`: create an endpoint; returns the descriptor or -1.
      import :: c_int
      !> Address family.
      integer(c_int), value :: domain
      !> Socket type.
      integer(c_int), value :: type
      !> Protocol, 0 for the default.
      integer(c_int), value :: protocol
      !> New descriptor, or -1.
      integer(c_int) :: fd
    end function c_socket
  end interface

  !> `setsockopt(2)` with an `int` option value; returns 0 or -1.
  interface
    function c_setsockopt(fd, level, name, value, length) bind(C, name='setsockopt') result(rc)
      !! `setsockopt(2)` with an `int` option value; returns 0 or -1.
      import :: c_int
      !> Socket descriptor.
      integer(c_int), value :: fd
      !> Option level.
      integer(c_int), value :: level
      !> Option name.
      integer(c_int), value :: name
      !> Option value.
      integer(c_int), intent(in) :: value
      !> Size of the value in bytes.
      integer(c_int), value :: length
      !> 0 on success, -1 on failure.
      integer(c_int) :: rc
    end function c_setsockopt
  end interface

  !> `bind(2)` with a 16-byte `struct sockaddr_in`; returns 0 or -1.
  interface
    function c_bind(fd, address, length) bind(C, name='bind') result(rc)
      !! `bind(2)` with a 16-byte `struct sockaddr_in`; returns 0 or -1.
      import :: c_int, c_int8_t
      !> Socket descriptor.
      integer(c_int), value :: fd
      !> The address bytes.
      integer(c_int8_t), intent(in) :: address(16)
      !> Size of the address in bytes.
      integer(c_int), value :: length
      !> 0 on success, -1 on failure.
      integer(c_int) :: rc
    end function c_bind
  end interface

  !> `listen(2)`; returns 0 or -1.
  interface
    function c_listen(fd, backlog) bind(C, name='listen') result(rc)
      !! `listen(2)`; returns 0 or -1.
      import :: c_int
      !> Socket descriptor.
      integer(c_int), value :: fd
      !> Length of the queue of pending connections.
      integer(c_int), value :: backlog
      !> 0 on success, -1 on failure.
      integer(c_int) :: rc
    end function c_listen
  end interface

  !> `accept(2)` without the peer address; returns the descriptor or -1.
  interface
    function c_accept(fd, address, length) bind(C, name='accept') result(client)
      !! `accept(2)` without the peer address; returns the descriptor or -1.
      import :: c_int, c_ptr
      !> Listening socket.
      integer(c_int), value :: fd
      !> Peer address buffer (NULL).
      type(c_ptr), value :: address
      !> Peer address length (NULL).
      type(c_ptr), value :: length
      !> Connected socket, or -1.
      integer(c_int) :: client
    end function c_accept
  end interface

  !> `recv(2)`; returns the number of bytes, 0 at end of stream, or -1.
  interface
    function c_recv(fd, buffer, length, flags) bind(C, name='recv') result(n)
      !! `recv(2)`; returns the number of bytes, 0 at end of stream, or -1.
      import :: c_int, c_char, c_size_t, c_intptr_t
      !> Socket descriptor.
      integer(c_int), value :: fd
      !> Receive buffer.
      character(kind=c_char), intent(out) :: buffer(*)
      !> Capacity of the buffer.
      integer(c_size_t), value :: length
      !> Flags, 0.
      integer(c_int), value :: flags
      !> Bytes received, 0 or -1.
      integer(c_intptr_t) :: n
    end function c_recv
  end interface

  !> `send(2)`; returns the number of bytes sent or -1.
  interface
    function c_send(fd, buffer, length, flags) bind(C, name='send') result(n)
      !! `send(2)`; returns the number of bytes sent or -1.
      import :: c_int, c_char, c_size_t, c_intptr_t
      !> Socket descriptor.
      integer(c_int), value :: fd
      !> Bytes to send.
      character(kind=c_char), intent(in) :: buffer(*)
      !> Number of bytes.
      integer(c_size_t), value :: length
      !> Flags (`MSG_NOSIGNAL`).
      integer(c_int), value :: flags
      !> Bytes sent, or -1.
      integer(c_intptr_t) :: n
    end function c_send
  end interface

  !> `close(2)`; returns 0 or -1.
  interface
    function c_close(fd) bind(C, name='close') result(rc)
      !! `close(2)`; returns 0 or -1.
      import :: c_int
      !> Descriptor to close.
      integer(c_int), value :: fd
      !> 0 on success, -1 on failure.
      integer(c_int) :: rc
    end function c_close
  end interface

  !> `shutdown(2)`; returns 0 or -1.
  interface
    function c_shutdown(fd, how) bind(C, name='shutdown') result(rc)
      !! `shutdown(2)`; returns 0 or -1.
      import :: c_int
      !> Socket descriptor.
      integer(c_int), value :: fd
      !> Direction (`SHUT_WR`).
      integer(c_int), value :: how
      !> 0 on success, -1 on failure.
      integer(c_int) :: rc
    end function c_shutdown
  end interface

  !> `poll(2)` on one descriptor; returns the number ready, 0 on timeout, -1.
  interface
    function c_poll(fds, count, timeout_ms) bind(C, name='poll') result(ready)
      !! `poll(2)` on one descriptor; returns the number ready, 0 on timeout, -1.
      import :: c_int, c_long, pollfd
      !> The descriptor to watch.
      type(pollfd), intent(inout) :: fds
      !> Number of entries, 1.
      integer(c_long), value :: count
      !> Timeout in milliseconds.
      integer(c_int), value :: timeout_ms
      !> Ready descriptors, 0 or -1 (also when interrupted by a signal).
      integer(c_int) :: ready
    end function c_poll
  end interface

  !> `clock_gettime(2)`; returns 0 or -1.
  interface
    function c_clock_gettime(clock, now) bind(C, name='clock_gettime') result(rc)
      !! `clock_gettime(2)`; returns 0 or -1.
      import :: c_int, timespec
      !> Clock id.
      integer(c_int), value :: clock
      !> Receives the time.
      type(timespec), intent(out) :: now
      !> 0 on success, -1 on failure.
      integer(c_int) :: rc
    end function c_clock_gettime
  end interface

  !> `exit(3)`: terminate the process with a status, without a STOP message.
  interface
    subroutine c_exit(status) bind(C, name='exit')
      !! `exit(3)`: terminate the process with a status, without a STOP message.
      import :: c_int
      !> Exit status.
      integer(c_int), value :: status
    end subroutine c_exit
  end interface

  !> `signal(2)`; returns the previous handler.
  interface
    function c_signal(signum, handler) bind(C, name='signal') result(previous)
      !! `signal(2)`; returns the previous handler.
      import :: c_int, c_funptr
      !> Signal number.
      integer(c_int), value :: signum
      !> New handler.
      type(c_funptr), value :: handler
      !> Previous handler.
      type(c_funptr) :: previous
    end function c_signal
  end interface

  !> `opendir(3)`; returns the stream or NULL.
  interface
    function c_opendir(path) bind(C, name='opendir') result(dir)
      !! `opendir(3)`; returns the stream or NULL.
      import :: c_char, c_ptr
      !> NUL-terminated directory path.
      character(kind=c_char), intent(in) :: path(*)
      !> Directory stream, or NULL.
      type(c_ptr) :: dir
    end function c_opendir
  end interface

  !> `readdir(3)`; returns the next entry or NULL at the end.
  interface
    function c_readdir(dir) bind(C, name='readdir') result(entry)
      !! `readdir(3)`; returns the next entry or NULL at the end.
      import :: c_ptr
      !> Directory stream.
      type(c_ptr), value :: dir
      !> Pointer to a `struct dirent`, or NULL.
      type(c_ptr) :: entry
    end function c_readdir
  end interface

  !> `closedir(3)`; returns 0 or -1.
  interface
    function c_closedir(dir) bind(C, name='closedir') result(rc)
      !! `closedir(3)`; returns 0 or -1.
      import :: c_ptr, c_int
      !> Directory stream.
      type(c_ptr), value :: dir
      !> 0 on success, -1 on failure.
      integer(c_int) :: rc
    end function c_closedir
  end interface

  !> `strlen(3)`.
  interface
    function c_strlen(text) bind(C, name='strlen') result(length)
      !! `strlen(3)`.
      import :: c_ptr, c_size_t
      !> NUL-terminated string.
      type(c_ptr), value :: text
      !> Length without the NUL.
      integer(c_size_t) :: length
    end function c_strlen
  end interface

contains

  !> Copy a Fortran string into a NUL-terminated C string.
  !>
  !> **Description:** The whole string is copied (trailing blanks
  !> included) and `c_null_char` is appended.
  !>
  !> **Business Justification:** Every C call that takes a path or SQL text
  !> needs a NUL-terminated string.
  !>
  !> **Returns:** The C string. **Errors:** None. **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `rc = c_opendir(to_c_string('/app/migrations'))`
  !>
  !> **See Also:** [[from_c_string]]
  pure function to_c_string(text) result(c_text)
    !> Fortran string.
    character(len=*), intent(in) :: text
    !> The text followed by NUL.
    character(kind=c_char, len=:), allocatable :: c_text
    c_text = text//c_null_char
  end function to_c_string

  !> Copy a NUL-terminated C string into a Fortran string.
  !>
  !> **Description:** A NULL pointer yields an empty string.
  !>
  !> **Business Justification:** SQLite error messages are C strings.
  !>
  !> **Returns:** The text without the NUL. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe while the C string lives.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `message = from_c_string(sqlite3_errmsg(db))`
  !>
  !> **See Also:** [[to_c_string]]
  function from_c_string(pointer) result(text)
    !> C string, or NULL.
    type(c_ptr), intent(in) :: pointer
    !> The copied text.
    character(len=:), allocatable :: text
    character(kind=c_char), pointer :: chars(:) !! The C string as characters.
    integer :: i !! Loop index.
    integer :: length !! Length of the value.

    text = ''
    if (.not. c_associated(pointer)) return
    length = int(c_strlen(pointer))
    call c_f_pointer(pointer, chars, [length])
    allocate (character(len=length) :: text)
    do i = 1, length
      text(i:i) = chars(i)
    end do
  end function from_c_string

  !> List the names in a directory.
  !>
  !> **Description:** Reads every entry with `readdir`, including `.` and
  !> `..`; the caller filters. `d_name` is read at its 64-bit Linux offset
  !> ([[digit_posix:dirent_name_offset]]).
  !>
  !> **Business Justification:** The migration runner applies every
  !> `NNNN_*.sql` file of the migrations directory (CLAUDE.md 6.1).
  !>
  !> **Returns:** `ok` false when the directory cannot be opened.
  !> **Errors:** See Returns. **Side Effects:** Reads the directory.
  !>
  !> **Complexity:** O(f) in the number of entries.
  !> **Thread Safety:** Not safe (`readdir` state).
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call list_directory('/app/migrations', names, ok)`
  !>
  !> **See Also:** [[store_migrate]]
  subroutine list_directory(path, names, ok)
    !> Directory path.
    character(len=*), intent(in) :: path
    !> Names of the entries, each padded to 255 characters.
    character(len=dirent_name_capacity - 1), allocatable, intent(out) :: names(:)
    !> True when the directory was read.
    logical, intent(out) :: ok
    type(c_ptr) :: dir !! Directory stream.
    type(c_ptr) :: entry !! Current `struct dirent`.
    character(kind=c_char), pointer :: bytes(:) !! The `struct dirent` as bytes.
    character(len=dirent_name_capacity - 1), allocatable :: grown(:) !! Names array grown by one.
    character(len=dirent_name_capacity - 1) :: name !! Name of the current entry.
    integer :: i !! Loop index.
    integer :: count !! Entries read so far.
    integer :: rc !! Return code of the C call.

    allocate (names(0))
    dir = c_opendir(to_c_string(path))
    ok = c_associated(dir)
    if (.not. ok) return
    count = 0
    do
      entry = c_readdir(dir)
      if (.not. c_associated(entry)) exit
      call c_f_pointer(entry, bytes, [dirent_name_offset + dirent_name_capacity])
      name = ''
      do i = 1, dirent_name_capacity - 1
        if (bytes(dirent_name_offset + i) == c_null_char) exit
        name(i:i) = bytes(dirent_name_offset + i)
      end do
      allocate (grown(count + 1))
      grown(1:count) = names
      grown(count + 1) = name
      call move_alloc(grown, names)
      count = count + 1
    end do
    rc = c_closedir(dir)
  end subroutine list_directory

  !> Signal handler for SIGTERM and SIGINT: request a graceful stop.
  !>
  !> **Description:** Only sets [[stop_requested]] and [[stop_signal]]; the
  !> server loop polls the flag at least every 200 ms.
  !>
  !> **Business Justification:** Graceful shutdown in at most 10 s
  !> (CLAUDE.md 6.1).
  !>
  !> **Errors:** None. **Side Effects:** Sets two module variables.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Async-signal-safe (plain
  !> stores).
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** installed by [[install_stop_handlers]].
  !>
  !> **See Also:** [[install_stop_handlers]]
  subroutine on_stop_signal(signum) bind(C)
    !> The received signal.
    integer(c_int), value :: signum
    stop_signal = signum
    stop_requested = .true.
  end subroutine on_stop_signal

  !> Install the stop handler for SIGTERM and SIGINT.
  !>
  !> **Description:** Uses `signal(2)`; the handler only sets a flag.
  !>
  !> **Business Justification:** `docker stop` sends SIGTERM.
  !>
  !> **Errors:** None. **Side Effects:** Changes the process signal
  !> dispositions.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Not safe; call once at start-up.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call install_stop_handlers()`
  !>
  !> **See Also:** [[on_stop_signal]]
  subroutine install_stop_handlers()
    type(c_funptr) :: previous !! Previous signal handler (unused).
    previous = c_signal(sigterm, c_funloc(on_stop_signal))
    previous = c_signal(sigint, c_funloc(on_stop_signal))
  end subroutine install_stop_handlers

end module digit_posix
