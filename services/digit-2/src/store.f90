! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/store.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         SQLite storage of the digit: opening the database,
!                  applying the versioned migrations and reading the row
!                  that holds the value and successor of the digit.
! Related Docs:    services/digit-2/README.md, migrations/0001_digit.sql,
!                  CLAUDE.md 4.4, ADR-0022

!> SQLite storage of the digit (open, migrate, read).
!>
!> **Description:** The digit service keeps its only fact, the value and
!> successor of its digit, in its own SQLite database (CLAUDE.md 4.4).
!> Migrations are the files `NNNN_*.sql` of the migrations directory,
!> applied once each in lexical order and recorded in `schema_migrations`.
!>
!> **Business Justification:** Each service owns its database (CLAUDE.md
!> 1, rule 4); the digit lives in the database, not the code.
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_sqlite]], [[digit_api]]
module digit_store
  use, intrinsic :: iso_c_binding, only: c_ptr, c_null_ptr, c_null_funptr, c_associated, c_int
  use digit_sqlite
  use digit_posix, only: to_c_string, from_c_string, list_directory
  use digit_log, only: log_write, level_info, level_error
  implicit none
  private

  public :: digit_row, store_t, store_open, store_migrate, store_read, store_exec, store_close

  !> Busy timeout of the connection, in milliseconds (CLAUDE.md 6.1).
  integer(c_int), parameter :: busy_timeout_ms = 2000
  !> Bookkeeping table of the migration runner: one row per applied file,
  !> `version` is the file name, `applied_at` the UTC time (ISO 8601).
  character(len=*), parameter :: migrations_table = 'CREATE TABLE IF NOT EXISTS schema_migrations ('// &
                                 ' version TEXT PRIMARY KEY NOT NULL,'// &
                                 ' applied_at TEXT NOT NULL) STRICT;'

  !> The digit row of the database (table `digit` of 0001_digit.sql).
  type :: digit_row
    !> The digit the service represents, 0..9.
    integer :: digit = -1
    !> Numeric value of the digit, 0..9.
    integer :: value = -1
    !> Successor of the digit in base 10, 0..9.
    integer :: next = -1
    !> True when the successor wraps to 0 (digit 9 only).
    logical :: carry = .false.
  end type digit_row

  !> An open SQLite connection (NULL when closed).
  type :: store_t
    !> The `sqlite3*` connection.
    type(c_ptr) :: db = c_null_ptr
  end type store_t

contains

  !> Open (or create) the SQLite database file.
  !>
  !> **Description:** Opens `path` read-write, creating it when missing,
  !> sets a busy timeout of 2 s and enables foreign keys.
  !>
  !> **Business Justification:** Each service owns its database.
  !>
  !> **Returns:** `ok` false when the file cannot be opened (`message`
  !> holds the SQLite text). **Errors:** See Returns.
  !> **Side Effects:** Creates the file when missing.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call store_open(st, '/data/digit-2.db', ok, message)`
  !>
  !> **See Also:** [[store_migrate]], [[store_close]]
  subroutine store_open(store, path, ok, message)
    !> Receives the connection.
    type(store_t), intent(out) :: store
    !> Database path, `:memory:` for an in-memory database.
    character(len=*), intent(in) :: path
    !> True on success.
    logical, intent(out) :: ok
    !> Reason of a failure, empty on success.
    character(len=:), allocatable, intent(out) :: message
    integer(c_int) :: rc !! Return code of the C call.
    message = ''
    rc = sqlite3_open_v2(to_c_string(path), store%db, ior(sqlite_open_readwrite, sqlite_open_create), c_null_ptr)
    ok = rc == sqlite_ok
    if (.not. ok) then
      message = 'cannot open the database: '//from_c_string(sqlite3_errmsg(store%db))
      call store_close(store)
      return
    end if
    rc = sqlite3_busy_timeout(store%db, busy_timeout_ms)
    call store_exec(store, 'PRAGMA foreign_keys = ON;', ok, message)
  end subroutine store_open

  !> Execute SQL statements without results.
  !>
  !> **Description:** Wraps `sqlite3_exec`; used by the migration runner and
  !> by the unit tests to change the row.
  !>
  !> **Business Justification:** One place where SQL errors become messages.
  !>
  !> **Returns:** `ok` false with the SQLite message on failure.
  !> **Errors:** See Returns. **Side Effects:** Whatever the SQL does.
  !>
  !> **Complexity:** That of the statements.
  !> **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call store_exec(st, 'UPDATE digit SET next = 7;', ok, message)`
  !>
  !> **See Also:** [[store_migrate]]
  subroutine store_exec(store, sql, ok, message)
    !> Open connection.
    type(store_t), intent(in) :: store
    !> SQL text.
    character(len=*), intent(in) :: sql
    !> True on success.
    logical, intent(out) :: ok
    !> SQLite message on failure, empty on success.
    character(len=:), allocatable, intent(out) :: message
    type(c_ptr) :: error !! Error message allocated by SQLite.
    integer(c_int) :: rc !! Return code of the C call.
    message = ''
    rc = sqlite3_exec(store%db, to_c_string(sql), c_null_funptr, c_null_ptr, error)
    ok = rc == sqlite_ok
    if (.not. ok) then
      if (c_associated(error)) then
        message = from_c_string(error)
      else
        message = from_c_string(sqlite3_errmsg(store%db))
      end if
    end if
    call sqlite3_free(error)
  end subroutine store_exec

  !> Apply the migrations of a directory that are not applied yet.
  !>
  !> **Description:** Creates `schema_migrations` when missing, lists the
  !> names of `dir` that end in `.sql` and do not start with a dot, sorts
  !> them lexically and applies each name not recorded yet, in one
  !> transaction per file together with its record. Running it again
  !> applies nothing.
  !>
  !> **Business Justification:** Migrations run at start-up and are
  !> versioned (CLAUDE.md 6.1); the seed of the digit is a migration.
  !>
  !> **Returns:** `applied` files; `ok` false with `message` when the
  !> directory or a file cannot be read or its SQL fails (that file is
  !> rolled back). **Errors:** See Returns.
  !> **Side Effects:** Reads files; writes the database; logs each file.
  !>
  !> **Complexity:** O(f^2 + s) for f files of total size s.
  !> **Thread Safety:** Not safe; call before serving.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call store_migrate(st, '/app/migrations', applied, ok, message)`
  !>
  !> **See Also:** [[store_read]]
  subroutine store_migrate(store, dir, applied, ok, message)
    !> Open connection.
    type(store_t), intent(in) :: store
    !> Directory with the migration files.
    character(len=*), intent(in) :: dir
    !> Number of files applied by this call.
    integer, intent(out) :: applied
    !> True on success.
    logical, intent(out) :: ok
    !> Reason of a failure, empty on success.
    character(len=:), allocatable, intent(out) :: message
    character(len=255), allocatable :: names(:) !! Names of the directory entries.
    character(len=255) :: swap !! Name being inserted while sorting.
    integer :: i !! Loop index.
    integer :: j !! Insertion position while sorting.
    integer :: n !! Number of names or characters.

    applied = 0
    call store_exec(store, migrations_table, ok, message)
    if (.not. ok) return
    call list_directory(dir, names, ok)
    if (.not. ok) then
      message = 'cannot read the migrations directory '//dir
      return
    end if
    names = pack(names, is_migration(names))
    n = size(names)
    do i = 2, n
      swap = names(i)
      j = i - 1
      do while (j >= 1)
        if (names(j) <= swap) exit
        names(j + 1) = names(j)
        j = j - 1
      end do
      names(j + 1) = swap
    end do
    do i = 1, n
      if (is_applied(store, trim(names(i)))) cycle
      call apply_file(store, dir, trim(names(i)), ok, message)
      if (.not. ok) return
      applied = applied + 1
    end do
  end subroutine store_migrate

  !> Whether a directory entry is a migration file.
  !>
  !> **Description:** Names ending in `.sql`, longer than the suffix and
  !> not starting with a dot.
  !>
  !> **Business Justification:** Only migration files are applied.
  !>
  !> **Returns:** True for a migration file. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `is_migration('0001_digit.sql')` is true.
  !>
  !> **See Also:** [[store_migrate]]
  elemental function is_migration(name) result(keep)
    !> Entry name, blank-padded.
    character(len=*), intent(in) :: name
    !> True for a migration file.
    logical :: keep
    integer :: n !! Number of names or characters.
    n = len_trim(name)
    keep = n > 4 .and. name(1:1) /= '.'
    if (keep) keep = name(max(n - 3, 1):n) == '.sql'
  end function is_migration

  !> Whether a migration is recorded in `schema_migrations`.
  !>
  !> **Description:** A failing query counts as "not applied", so that the
  !> following apply fails loudly instead of skipping silently.
  !>
  !> **Business Justification:** Each migration runs exactly once.
  !>
  !> **Returns:** True when recorded. **Errors:** None (see Description).
  !> **Side Effects:** One SELECT.
  !>
  !> **Complexity:** O(log m). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `if (.not. is_applied(st, '0001_digit.sql')) ...`
  !>
  !> **See Also:** [[store_migrate]]
  function is_applied(store, version) result(applied)
    !> Open connection.
    type(store_t), intent(in) :: store
    !> Migration file name.
    character(len=*), intent(in) :: version
    !> True when recorded.
    logical :: applied
    type(c_ptr) :: stmt !! Prepared statement.
    character(len=:), allocatable :: c_version !! NUL-terminated version, alive until the step.
    integer(c_int) :: rc !! Return code of the C call.
    applied = .false.
    c_version = to_c_string(version)
    rc = sqlite3_prepare_v2(store%db, to_c_string('SELECT 1 FROM schema_migrations WHERE version = ?1;'), -1_c_int, &
                            stmt, c_null_ptr)
    if (rc == sqlite_ok) then
      rc = sqlite3_bind_text(stmt, 1_c_int, c_version, -1_c_int, c_null_funptr)
      applied = sqlite3_step(stmt) == sqlite_row
    end if
    rc = sqlite3_finalize(stmt)
  end function is_applied

  !> Apply one migration file and record it, in one transaction.
  !>
  !> **Description:** On any failure the transaction is rolled back.
  !>
  !> **Business Justification:** A half-applied migration must never be
  !> recorded as applied.
  !>
  !> **Returns:** `ok` false with `message` on failure. **Errors:** The file
  !> cannot be read, or its SQL or the record fails.
  !> **Side Effects:** Writes the database; logs the applied file.
  !>
  !> **Complexity:** O(s) in the file size.
  !> **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call apply_file(st, '/app/migrations', '0001_digit.sql', ok, message)`
  !>
  !> **See Also:** [[store_migrate]]
  subroutine apply_file(store, dir, version, ok, message)
    !> Open connection.
    type(store_t), intent(in) :: store
    !> Migrations directory.
    character(len=*), intent(in) :: dir
    !> Migration file name inside `dir`.
    character(len=*), intent(in) :: version
    !> True on success.
    logical, intent(out) :: ok
    !> Reason of a failure, empty on success.
    character(len=:), allocatable, intent(out) :: message
    character(len=:), allocatable :: sql !! SQL of the migration file.
    character(len=:), allocatable :: ignored !! Message of the rollback (ignored).
    logical :: rolled_back !! Outcome of the rollback (ignored).

    call read_file(dir//'/'//version, sql, ok)
    if (.not. ok) then
      message = 'cannot read migration '//dir//'/'//version
      return
    end if
    call store_exec(store, 'BEGIN IMMEDIATE;', ok, message)
    if (ok) call store_exec(store, sql, ok, message)
    if (ok) call store_exec(store, 'INSERT INTO schema_migrations (version, applied_at) VALUES ('''//version// &
                            ''', strftime(''%Y-%m-%dT%H:%M:%fZ'', ''now''));', ok, message)
    if (ok) call store_exec(store, 'COMMIT;', ok, message)
    if (.not. ok) then
      message = 'migration '//version//' failed: '//message
      call store_exec(store, 'ROLLBACK;', rolled_back, ignored)
      return
    end if
    call log_write(level_info, 'migration applied', detail=version)
  end subroutine apply_file

  !> Read a whole file into a string.
  !>
  !> **Description:** Stream access; the content is returned unchanged.
  !>
  !> **Business Justification:** Each migration file is one SQL script.
  !>
  !> **Returns:** `ok` false when the file cannot be opened or read.
  !> **Errors:** See Returns. **Side Effects:** Reads the file.
  !>
  !> **Complexity:** O(s). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call read_file('/app/migrations/0001_digit.sql', sql, ok)`
  !>
  !> **See Also:** [[apply_file]]
  subroutine read_file(path, content, ok)
    !> File path.
    character(len=*), intent(in) :: path
    !> The content.
    character(len=:), allocatable, intent(out) :: content
    !> True on success.
    logical, intent(out) :: ok
    integer :: unit !! File unit.
    integer :: status !! I/O or environment status code.
    integer :: size !! File size in bytes.
    content = ''
    open (newunit=unit, file=path, access='stream', form='unformatted', action='read', status='old', iostat=status)
    ok = status == 0
    if (.not. ok) return
    inquire (unit=unit, size=size)
    if (size > 0) then
      deallocate (content)
      allocate (character(len=size) :: content)
      read (unit, iostat=status) content
      ok = status == 0
    end if
    close (unit)
  end subroutine read_file

  !> Read the digit row.
  !>
  !> **Description:** Requires the table `digit` to hold exactly one row;
  !> zero rows or more than one are an error, as is any SQLite failure.
  !>
  !> **Business Justification:** GET /value, GET /next and GET /health
  !> answer from this read on every request (CLAUDE.md 4.4).
  !>
  !> **Returns:** `ok` false with `message` when the query fails or the
  !> table does not hold exactly one row; `row` is then untouched.
  !> **Errors:** See Returns. **Side Effects:** One SELECT.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call store_read(st, row, ok, message)`
  !>
  !> **See Also:** [[digit_row]]
  subroutine store_read(store, row, ok, message)
    !> Open, migrated connection.
    type(store_t), intent(in) :: store
    !> Receives the row on success.
    type(digit_row), intent(inout) :: row
    !> True on success.
    logical, intent(out) :: ok
    !> Reason of a failure, empty on success.
    character(len=:), allocatable, intent(out) :: message
    type(c_ptr) :: stmt !! Prepared statement.
    type(digit_row) :: found !! Row read before the uniqueness check.
    integer(c_int) :: rc !! Return code of the C call.
    ok = .false.
    message = ''
    rc = sqlite3_prepare_v2(store%db, to_c_string('SELECT digit, value, next, carry FROM digit LIMIT 2;'), -1_c_int, &
                            stmt, c_null_ptr)
    if (rc /= sqlite_ok) then
      message = from_c_string(sqlite3_errmsg(store%db))
    else if (sqlite3_step(stmt) /= sqlite_row) then
      message = 'the table digit holds no row'
    else
      found%digit = sqlite3_column_int(stmt, 0_c_int)
      found%value = sqlite3_column_int(stmt, 1_c_int)
      found%next = sqlite3_column_int(stmt, 2_c_int)
      found%carry = sqlite3_column_int(stmt, 3_c_int) /= 0
      if (sqlite3_step(stmt) == sqlite_done) then
        row = found
        ok = .true.
      else
        message = 'the table digit holds more than one row'
      end if
    end if
    rc = sqlite3_finalize(stmt)
    if (.not. ok) call log_write(level_error, 'cannot read the digit from the database', detail=message)
  end subroutine store_read

  !> Close the connection (a closed store is a no-op).
  !>
  !> **Description:** Sets the handle to NULL.
  !>
  !> **Business Justification:** Graceful shutdown leaves the database
  !> consistent (CLAUDE.md 6.1).
  !>
  !> **Errors:** None. **Side Effects:** Releases the connection.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call store_close(st)`
  !>
  !> **See Also:** [[store_open]]
  subroutine store_close(store)
    !> Connection to close.
    type(store_t), intent(inout) :: store
    integer(c_int) :: rc !! Return code of the C call.
    if (c_associated(store%db)) rc = sqlite3_close(store%db)
    store%db = c_null_ptr
  end subroutine store_close

end module digit_store
