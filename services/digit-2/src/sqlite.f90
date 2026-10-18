! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/sqlite.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         Fortran interfaces to the SQLite C API (the subset the
!                  service uses) through ISO_C_BINDING.
! Related Docs:    services/digit-2/README.md, ADR-0024

!> SQLite C API for Fortran.
!>
!> **Description:** `bind(C)` interfaces to `libsqlite3` and the result
!> codes the service checks. Strings passed to SQLite must be
!> NUL-terminated ([[to_c_string]]).
!>
!> **Business Justification:** The digit lives in the service's own SQLite
!> database and is read from Fortran (CLAUDE.md 4.4).
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_store]]
module digit_sqlite
  use, intrinsic :: iso_c_binding, only: c_char, c_int, c_ptr, c_funptr
  implicit none
  private

  public :: sqlite_ok, sqlite_row, sqlite_done, sqlite_open_readwrite, sqlite_open_create
  public :: sqlite3_open_v2, sqlite3_close, sqlite3_busy_timeout, sqlite3_exec, sqlite3_free, sqlite3_errmsg
  public :: sqlite3_prepare_v2, sqlite3_bind_text, sqlite3_step, sqlite3_column_int, sqlite3_finalize

  !> Result code: success.
  integer(c_int), parameter :: sqlite_ok = 0
  !> Result code of `sqlite3_step`: a row is available.
  integer(c_int), parameter :: sqlite_row = 100
  !> Result code of `sqlite3_step`: the statement has finished.
  integer(c_int), parameter :: sqlite_done = 101
  !> Open flag: read and write.
  integer(c_int), parameter :: sqlite_open_readwrite = 2
  !> Open flag: create the file when missing.
  integer(c_int), parameter :: sqlite_open_create = 4

  !> Open a database connection.
  interface
    function sqlite3_open_v2(filename, db, flags, vfs) bind(C, name='sqlite3_open_v2') result(rc)
      !! Open a database connection.
      import :: c_char, c_ptr, c_int
      !> NUL-terminated file name.
      character(kind=c_char), intent(in) :: filename(*)
      !> Receives the connection (also on most failures).
      type(c_ptr), intent(out) :: db
      !> Open flags.
      integer(c_int), value :: flags
      !> VFS name, NULL for the default.
      type(c_ptr), value :: vfs
      !> Result code.
      integer(c_int) :: rc
    end function sqlite3_open_v2
  end interface

  !> Close a connection (NULL is a no-op).
  interface
    function sqlite3_close(db) bind(C, name='sqlite3_close') result(rc)
      !! Close a connection (NULL is a no-op).
      import :: c_ptr, c_int
      !> Connection.
      type(c_ptr), value :: db
      !> Result code.
      integer(c_int) :: rc
    end function sqlite3_close
  end interface

  !> Set the busy timeout in milliseconds.
  interface
    function sqlite3_busy_timeout(db, ms) bind(C, name='sqlite3_busy_timeout') result(rc)
      !! Set the busy timeout in milliseconds.
      import :: c_ptr, c_int
      !> Connection.
      type(c_ptr), value :: db
      !> Timeout in milliseconds.
      integer(c_int), value :: ms
      !> Result code.
      integer(c_int) :: rc
    end function sqlite3_busy_timeout
  end interface

  !> Run SQL statements without a result callback.
  interface
    function sqlite3_exec(db, sql, callback, argument, errmsg) bind(C, name='sqlite3_exec') result(rc)
      !! Run SQL statements without a result callback.
      import :: c_ptr, c_char, c_funptr, c_int
      !> Connection.
      type(c_ptr), value :: db
      !> NUL-terminated SQL text.
      character(kind=c_char), intent(in) :: sql(*)
      !> Callback, NULL.
      type(c_funptr), value :: callback
      !> Callback argument, NULL.
      type(c_ptr), value :: argument
      !> Receives an error message to free with sqlite3_free, or NULL.
      type(c_ptr), intent(out) :: errmsg
      !> Result code.
      integer(c_int) :: rc
    end function sqlite3_exec
  end interface

  !> Free memory allocated by SQLite.
  interface
    subroutine sqlite3_free(pointer) bind(C, name='sqlite3_free')
      !! Free memory allocated by SQLite.
      import :: c_ptr
      !> Memory to free, or NULL.
      type(c_ptr), value :: pointer
    end subroutine sqlite3_free
  end interface

  !> Message of the last error of a connection.
  interface
    function sqlite3_errmsg(db) bind(C, name='sqlite3_errmsg') result(message)
      !! Message of the last error of a connection.
      import :: c_ptr
      !> Connection.
      type(c_ptr), value :: db
      !> NUL-terminated message owned by SQLite.
      type(c_ptr) :: message
    end function sqlite3_errmsg
  end interface

  !> Compile one SQL statement.
  interface
    function sqlite3_prepare_v2(db, sql, nbyte, stmt, tail) bind(C, name='sqlite3_prepare_v2') result(rc)
      !! Compile one SQL statement.
      import :: c_ptr, c_char, c_int
      !> Connection.
      type(c_ptr), value :: db
      !> NUL-terminated SQL text.
      character(kind=c_char), intent(in) :: sql(*)
      !> Length of the SQL, -1 up to the NUL.
      integer(c_int), value :: nbyte
      !> Receives the statement.
      type(c_ptr), intent(out) :: stmt
      !> Unused rest of the SQL, NULL.
      type(c_ptr), value :: tail
      !> Result code.
      integer(c_int) :: rc
    end function sqlite3_prepare_v2
  end interface

  !> Bind a text parameter; the text must outlive the statement step
  !> (destructor NULL, `SQLITE_STATIC`).
  interface
    function sqlite3_bind_text(stmt, index, text, nbyte, destructor) bind(C, name='sqlite3_bind_text') result(rc)
      !! Bind a text parameter; the text must outlive the statement step (destructor NULL, `SQLITE_STATIC`).
      import :: c_ptr, c_int, c_char, c_funptr
      !> Statement.
      type(c_ptr), value :: stmt
      !> Parameter index, from 1.
      integer(c_int), value :: index
      !> NUL-terminated text.
      character(kind=c_char), intent(in) :: text(*)
      !> Length, -1 up to the NUL.
      integer(c_int), value :: nbyte
      !> Destructor, NULL for `SQLITE_STATIC`.
      type(c_funptr), value :: destructor
      !> Result code.
      integer(c_int) :: rc
    end function sqlite3_bind_text
  end interface

  !> Run a statement one step.
  interface
    function sqlite3_step(stmt) bind(C, name='sqlite3_step') result(rc)
      !! Run a statement one step.
      import :: c_ptr, c_int
      !> Statement.
      type(c_ptr), value :: stmt
      !> `sqlite_row`, `sqlite_done` or an error code.
      integer(c_int) :: rc
    end function sqlite3_step
  end interface

  !> Integer value of a result column.
  interface
    function sqlite3_column_int(stmt, column) bind(C, name='sqlite3_column_int') result(value)
      !! Integer value of a result column.
      import :: c_ptr, c_int
      !> Statement positioned on a row.
      type(c_ptr), value :: stmt
      !> Column index, from 0.
      integer(c_int), value :: column
      !> The value.
      integer(c_int) :: value
    end function sqlite3_column_int
  end interface

  !> Destroy a statement (NULL is a no-op).
  interface
    function sqlite3_finalize(stmt) bind(C, name='sqlite3_finalize') result(rc)
      !! Destroy a statement (NULL is a no-op).
      import :: c_ptr, c_int
      !> Statement.
      type(c_ptr), value :: stmt
      !> Result code of the last step.
      integer(c_int) :: rc
    end function sqlite3_finalize
  end interface

end module digit_sqlite
