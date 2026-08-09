# DBInterface.jl Documentation

```@contents
```
*DBInterface.jl* provides interface definitions to allow common database operations to be implemented consistently
across various database packages.

## User Contract

A database driver defines the concrete connection, statement, and result types. Prefer the do-block forms of [`DBInterface.connect`](@ref), [`DBInterface.prepare`](@ref), and [`DBInterface.execute`](@ref) when the resource should be closed immediately after an operation.

SQL placeholder syntax is database- and driver-specific. Positional placeholders may use `?`, `$1`, or another form. Named placeholders may not be supported. One placeholder normally binds one scalar value, so a collection does not normally expand into an SQL `IN` list.

DBInterface does not parse, escape, validate, or sanitize SQL. Bind untrusted values as parameters. Do not interpolate them into SQL text. Parameters cannot safely replace identifiers, keywords, or SQL fragments; use a driver-specific identifier-quoting API for dynamic identifiers.

## Driver Contract

A driver should implement these core methods:

  * [`DBInterface.connect`](@ref) for its database or connection selector.
  * [`DBInterface.prepare`](@ref) for its [`DBInterface.Connection`](@ref) subtype.
  * [`DBInterface.execute`](@ref) for its [`DBInterface.Statement`](@ref) subtype.
  * [`DBInterface.getconnection`](@ref) for its statement subtype.
  * [`DBInterface.close!`](@ref) for its connections, statements, and result cursors.

The generic connection form of `execute` prepares a statement and returns the driver's cursor. If that cursor depends on the statement, the driver must keep the statement alive for the cursor's lifetime and release it when the cursor is closed or collected.

Each cursor row must support `propertynames`, `getproperty`, `length`, and positional `getindex`. A cursor should implement the Tables.jl row-table interface. Statements that return no rows must still return an empty cursor or iterator. The scoped `execute(f, ...)` forms call `DBInterface.close!` on the cursor.

Drivers can override [`DBInterface.transaction`](@ref), [`DBInterface.executemany`](@ref), [`DBInterface.executemultiple`](@ref), and [`DBInterface.lastrowid`](@ref) when the generic behavior does not match the database.

## Functions
```@docs
DBInterface.connect
DBInterface.@sql_str
DBInterface.getconnection
DBInterface.prepare
DBInterface.@prepare
DBInterface.execute
DBInterface.transaction
DBInterface.executemany
DBInterface.executemultiple
DBInterface.close!
DBInterface.lastrowid
DBInterface.ParameterError
DBInterface.Error
DBInterface.Warning
```

## Types

```@docs
DBInterface.Connection
DBInterface.Statement
DBInterface.Cursor
DBInterface.PositionalStatementParams
DBInterface.NamedStatementParams
DBInterface.StatementParams
```
