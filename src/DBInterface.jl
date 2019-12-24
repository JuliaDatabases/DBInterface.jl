module DBInterface

"Database packages should subtype `DBInterface.Connection` which represents a connection to a database"
abstract type Connection end

"""
    DBInterface.connect(DB, args...; kw...) => DBInterface.Connection

Database packages should overload `DBInterface.connect` for a specific `DB` `DBInterface.Connection` subtype
that returns a valid, live database connection that can be queried against.
"""
function connect end

connect(T, args...; kw...) = throw(NotImplementedError("`DBInterface.connect` not implemented for `$T`"))

"""
    DBInterface.close!(conn::DBInterface.Connection)

Immediately closes a database connection so further queries cannot be processed.
"""
function close! end

close!(conn::DBInterface.Connection) = throw(NotImplementedError("`DBInterface.close!` not implemented for `$(typeof(conn))`"))

"Database packages should provide a `DBInterface.Statement` subtype which represents a valid, prepared SQL statement that can be executed repeatedly"
abstract type Statement end

"""
    DBInterface.prepare(conn::DBInterface.Connection, sql::AbstractString) => DBInterface.Statement

Database packages should overload `DBInterface.prepare` for a specific `DBInterface.Connection` subtype, that validates and prepares
a SQL statement given as an `AbstractString` `sql` argument, and returns a `DBInterface.Statement` subtype. It is expected
that `DBInterface.Statement`s are only valid for the lifetime of the `DBInterface.Connection` object against which they are prepared.
"""
function prepare end

prepare(conn::DBInterface.Connection, sql::AbstractString) = throw(NotImplementedError("`DBInterface.prepare` not implemented for `$(typeof(conn))`"))

"Any object that iterates \"rows\", which are objects that are property-accessible and indexable. See `DBInterface.execute!` for more details on fetching query results."
abstract type Cursor end

"""
    DBInterface.execute!(conn::DBInterface.Connection, sql::AbstractString, args...; kw...) => DBInterface.Cursor
    DBInterface.execute!(stmt::DBInterface.Statement, args...; kw...) => DBInterface.Cursor

Database packages should overload `DBInterface.execute!` for a valid, prepared `DBInterface.Statement` subtype (the first method
signature is defined in DBInterface.jl using `DBInterface.prepare`), which takes zero or more `args` or `kw` arguments that should
be bound against the `stmt` (`args` as positional parameters, `kw` as named parameters, but not mixed) before executing the query
against the database. `DBInterface.execute!` should return a valid `DBInterface.Cursor` object, which is any iterator of "rows",
which themselves must be property-accessible (i.e. implement `propertynames` and `getproperty` for value access by name),
and indexable (i.e. implement `length` and `getindex` for value access by index). These "result" objects do not need
to subtype `DBInterface.Cursor` explicitly as long as they satisfy the interface. For DDL/DML SQL statements, which typically
do not return results, an iterator is still expected to be returned that just iterates `nothing`, i.e. an "empty" iterator.
"""
function execute! end

execute!(stmt::DBInterface.Statement, args...; kw...) = throw(NotImplementedError("`DBInterface.execute!` not implemented for `$(typeof(stmt))`"))

DBInterface.execute!(conn::Connection, sql::AbstractString, args...; kw...) = DBInterface.execute!(DBInterface.prepare(conn, sql), args...; kw...)

struct ParameterError
    msg::String
end

"""
    DBInterface.executemany!(conn::DBInterface.Connect, sql::AbstractString, args...; kw...) => Nothing
    DBInterface.executemany!(stmt::DBInterface.Statement, args...; kw...) => Nothing

Similar to 
"""
function executemany!(stmt::DBInterface.Statement, args...; kw...)
    if !isempty(args)
        arg = args[1]
        len = length(arg)
        all(x -> length(x) == len, args) || throw(ParameterError("positional parameters provided to `DBInterface.executemany!` do not all have the same number of parameters"))
        for i = 1:len
            xargs = map(x -> x[i], args)
            DBInterface.execute!(stmt, xargs...)
        end
    elseif !isempty(kw)
        k = kw[1]
        len = length(k)
        all(x -> length(x) == len, kw) || throw(ParameterError("named parameters provided to `DBInterface.executemany!` do not all have the same number of parameters"))
        for i = 1:len
            xargs = collect(k=>v[i] for (k, v) in kw)
            DBInterface.execute!(stmt; xargs...)
        end
    else
        DBInterface.execute!(stmt)
    end
    return
end

DBInterface.executemany!(conn::Connection, sql::AbstractString, args...; kw...) = DBInterface.executemany!(DBInterface.prepare(conn, sql), args...; kw...)

"""
    DBInterface.close!(x::Cursor) => Nothing

Immediately close a resultset cursor. Database packages should overload for the provided resultset `Cursor` object.
"""
close!(x) = throw(NotImplementedError("`DBInterface.close!` not implemented for `$(typeof(x))`"))

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
