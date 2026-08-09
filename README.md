# DBInterface.jl

[![deps](https://juliahub.com/docs/DBInterface/deps.svg)](https://juliahub.com/ui/Packages/DBInterface/bSj9k?t=2)
[![version](https://juliahub.com/docs/DBInterface/version.svg)](https://juliahub.com/ui/Packages/DBInterface/bSj9k)
[![pkgeval](https://juliahub.com/docs/DBInterface/pkgeval.svg)](https://juliahub.com/ui/Packages/DBInterface/bSj9k)

## Purpose

DBInterface.jl defines a small, common interface for Julia database drivers. Select a driver package, then use the `DBInterface` methods against that driver's connection, statement, and result types.

## Basic Use

Use the do-block forms when a connection, statement, or result should be closed at the end of an operation:

```julia
using DBInterface

DBInterface.connect(Driver.Connection, args...; kwargs...) do conn
    DBInterface.execute(conn, "SELECT id, name FROM users WHERE id = ?", (42,)) do cursor
        for row in cursor
            @show row.id
            @show row[2]
        end
    end

    DBInterface.prepare(conn, "INSERT INTO users (id, name) VALUES (?, ?)") do stmt
        DBInterface.execute(_ -> nothing, stmt, (43, "Ada"))
    end
end
```

Rows must support property access by column name and indexing by column position. Result cursors should also satisfy the Tables.jl row-table interface, so Tables.jl-compatible sinks can consume them:

```julia
df = DBInterface.execute(DataFrame, conn, "SELECT * FROM users")
DBInterface.execute(cursor -> CSV.write("users.csv", cursor), conn, "SELECT * FROM users")
```

Use `executemany` for column-oriented bulk parameters. Each parameter collection must have the same length:

```julia
DBInterface.executemany(
    conn,
    "INSERT INTO users (id, name) VALUES (?, ?)",
    ([1, 2, 3], ["Ada", "Grace", "Katherine"]),
)
```

Named parameters can be passed as a `NamedTuple`, an `AbstractDict`, or keywords when the database and driver support named placeholders:

```julia
DBInterface.execute(conn, "SELECT * FROM users WHERE id = :id", (id=42,))
DBInterface.execute(conn, "SELECT * FROM users WHERE id = :id"; id=42)
```

Placeholder syntax is driver-specific. For example, a driver may require `?`, `:name`, `$1`, or another form. One placeholder normally binds one scalar value. A collection does not normally expand into an SQL `IN` list.

## SQL Safety

DBInterface passes SQL text to the driver unchanged. Use bound parameters for untrusted values. Do not interpolate untrusted data into SQL strings. Bound parameters do not quote table names, column names, SQL keywords, or other SQL fragments. Use the driver's identifier-quoting API when an identifier must be dynamic.

The `sql"..."` string macro does not parse, escape, validate, or sanitize SQL.

## Driver Authors

See the [documentation](https://juliadatabases.org/DBInterface.jl/dev) for the required methods, result contract, resource ownership rules, and optional extensions.
