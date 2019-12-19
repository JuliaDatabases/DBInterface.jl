module DBI

"Database packages should subtype `DBI.Connection` which represents a connection to a database"
abstract type Connection end

"""
    DBI.connect(DB, args...; kw...) => DBI.Connection

Database packages should overload `DBI.connect` for a specific `DB` `DBI.Connection` subtype
that returns a valid, live database connection that can be queried against.
"""
function connect end

connect(T, args...; kw...) = throw(NotImplementedError("`DBI.connect` not implemented for `$T`"))

"""
    DBI.close!(conn::DBI.Connection)

Immediately closes a database connection so further queries cannot be processed.
"""
function close! end

close!(conn::DBI.Connection) = throw(NotImplementedError("`DBI.close!` not implemented for `$(typeof(conn))`"))

"Database packages should provide a `DBI.Statement` subtype which represents a valid, prepared SQL statement that can be executed repeatedly"
abstract type Statement end

"""
    DBI.prepare(conn::DBI.Connection, sql::AbstractString) => DBI.Statement

Database packages should overload `DBI.prepare` for a specific `DBI.Connection` subtype, that validates and prepares
a SQL statement given as an `AbstractString` `sql` argument, and returns a `DBI.Statement` subtype. It is expected
that `DBI.Statement`s are only valid for the lifetime of the `DBI.Connection` object against which they are prepared.
"""
function prepare end

prepare(conn::DBI.Connection, sql::AbstractString) = throw(NotImplementedError("`DBI.prepare` not implemented for `$(typeof(conn))`"))

"Any object that iterates \"rows\", which are objects that are property-accessible and indexable. See `DBI.execute!` for more details on fetching query results."
abstract type Cursor end

"""
    DBI.execute!(conn::DBI.Connection, sql::AbstractString, args...; kw...) => DBI.Cursor
    DBI.execute!(stmt::DBI.Statement, args...; kw...) => DBI.Cursor

Database packages should overload `DBI.execute!` for a valid, prepared `DBI.Statement` subtype (the first method
signature is defined in DBI.jl using `DBI.prepare`), which takes zero or more `args` or `kw` arguments that should
be bound against the `stmt` (`args` as positional parameters, `kw` as named parameters, but not mixed) before executing the query
against the database. `DBI.execute!` should return a valid `DBI.Cursor` object, which is any iterator of "rows",
which themselves must be property-accessible (i.e. implement `propertynames` and `getproperty` for value access by name),
and indexable (i.e. implement `length` and `getindex` for value access by index). These "result" objects do not need
to subtype `DBI.Cursor` explicitly as long as they satisfy the interface. For DDL/DML SQL statements, which typically
do not return results, an iterator is still expected to be returned that just iterates `nothing`, i.e. an "empty" iterator.
"""
function execute! end

execute!(stmt::DBI.Statement, args...; kw...) = throw(NotImplementedError("`DBI.execute!` not implemented for `$(typeof(stmt))`"))

DBI.execute!(conn::Connection, sql::AbstractString, args...; kw...) = DBI.execute!(DBI.prepare(conn, sql), args...; kw...)

struct ParameterError
    msg::String
end

"""
    DBI.executemany!(conn::DBI.Connect, sql::AbstractString, args...; kw...) => Nothing
    DBI.executemany!(stmt::DBI.Statement, args...; kw...) => Nothing

Similar to 
"""
function executemany!(stmt::DBI.Statement, args...; kw...)
    if !isempty(args)
        arg = args[1]
        len = length(arg)
        all(x -> length(x) == len, args) || throw(ParameterError("positional parameters provided to `DBI.executemany!` do not all have the same number of parameters"))
        for i = 1:len
            xargs = map(x -> x[i], args)
            DBI.execute!(stmt, xargs...)
        end
    else # !isempty(kw)
        k = kw[1]
        len = length(k)
        all(x -> length(x) == len, kw) || throw(ParameterError("named parameters provided to `DBI.executemany!` do not all have the same number of parameters"))
        for i = 1:len
            xargs = collect(k=>v[i] for (k, v) in kw)
            DBI.execute!(stmt; xargs...)
        end
    end
    return
end

DBI.executemany!(conn::Connection, sql::AbstractString, args...; kw...) = DBI.executemany!(DBI.prepare(conn, sql), args...; kw...)

"""
    DBI.close!(x::Cursor) => Nothing

Immediately close a resultset cursor. Database packages should overload for the provided resultset `Cursor` object.
"""
close!(x) = throw(NotImplementedError("`DBI.close!` not implemented for `$(typeof(x))`"))

# exception handling
"Error for signaling a database package hasn't implemented an interface method"
struct NotImplementedError <: Exception
    msg::String
end

"Standard warning object for various database operations"
struct Warning
    msg::String
end

"Fallback, generic error object for database operations"
struct Error <: Exception
    msg::String
end

end # module
