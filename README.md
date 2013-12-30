DBI.jl
======

The DBI package is meant to provide a database-independent API that all database drivers can be expected to comply with. This makes it easy to write code that can be easily ported between different databases. The inspiration for this comes from the classic Perl DBI module, which has a nice tutorial at [http://www.perl.com/pub/1999/10/DBI.html](http://www.perl.com/pub/1999/10/DBI.html).

The current draft API is described below:

* Types
    * DatabaseSystem: ODBC, SQLite, ...
    * DatabaseHandle: Connection to a database
    * StatementHandle: 
* Functions
    * columninfo: Get basic information about column:
        * Type: INT, VARCHAR, ...
        * Nullable: true, false
        * Autoincrement: true, false
        * Primary key: true, false
    * connect/disconnect: Set up and shut down connections to database
    * prepare: Let the database prepare, but not execute, a SQL statement
    * execute: Execute a SQL statement, potentially with per-call bindings
    * fetchall: Fetch all rows as an array of arrays
    * fetchrow: Fetch a row as an Array{Any}
    * finish: Finalize a SQL statement's execution
    * sqlescape: Escape a SQL statement to prevent injections
    * tableinfo: Get metdata about a table
