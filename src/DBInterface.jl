module DBInterface

"""
Declare the string as written in SQL.

The macro doesn't do any processing of the string.
"""
macro sql_str(cmd)
    cmd
end

"Database packages should subtype `DBInterface.Connection` which represents a connection to a database"
abstract type Connection end

"""
    DBInterface.connect(DB, args...; kw...) => DBInterface.Connection

Database packages should overload `DBInterface.connect` for a specific `DB` `DBInterface.Connection` subtype
that returns a valid, live database connection that can be queried against.
"""
function connect end

# Different `close!` signatures have their own docstrings.
function close! end

"""
    DBInterface.close!(conn::DBInterface.Connection)

Immediately closes a database connection so further queries cannot be processed.
"""
close!(conn::Connection)


"Database packages should provide a `DBInterface.Statement` subtype which represents a valid, prepared SQL statement that can be executed repeatedly"
abstract type Statement end

"""
    DBInterface.prepare(conn::DBInterface.Connection, sql::AbstractString) => DBInterface.Statement
    DBInterface.prepare(f::Function, sql::AbstractString) => DBInterface.Statement

Database packages should overload `DBInterface.prepare` for a specific `DBInterface.Connection` subtype, that validates and prepares
a SQL statement given as an `AbstractString` `sql` argument, and returns a `DBInterface.Statement` subtype. It is expected
that `DBInterface.Statement`s are only valid for the lifetime of the `DBInterface.Connection` object against which they are prepared.
For convenience, users may call `DBInterface.prepare(f::Function, sql)` which first calls `f()` to retrieve a valid `DBInterface.Connection`
before calling `DBInterface.prepare(conn, sql)`; this allows deferring connection retrieval and thus statement preparation until runtime,
which is often convenient when building applications.
"""
function prepare end

prepare(f::Function, sql::AbstractString) = prepare(f(), sql)

const PREPARED_STMTS = Dict{Symbol, Statement}()

"""
    DBInterface.@prepare f sql

Takes a `DBInterface.Connection`-retrieval function `f` and SQL statement `sql` and will return a prepared statement, via usage of `DBInterface.prepare`.
If the statement has already been prepared, it will be re-used (prepared statements are cached).
"""
macro prepare(getDB, sql)
    key = gensym()
    return quote
        get!(DBInterface.PREPARED_STMTS, $(QuoteNode(key))) do
            DBInterface.prepare($(esc(getDB)), $sql)
        end
    end
end

"""
    DBInterface.close!(stmt::DBInterface.Statement)

Close a prepared statement so further queries cannot be executed.
"""
close!(stmt::Statement)

"Any object that iterates \"rows\", which are objects that are property-accessible and indexable. See `DBInterface.execute` for more details on fetching query results."
abstract type Cursor end


"""
The container types for positional statement parameters supported by `DBInterface.execute`
"""
const PositionalStatementParams = Union{AbstractVector, Tuple}

"""
The container types for named statement parameters supported by `DBInterface.execute`
"""
const NamedStatementParams = Union{AbstractDict, NamedTuple}

"""
The container types for statement parameters supported by `DBInterface.execute`
"""
const StatementParams = Union{PositionalStatementParams, NamedStatementParams}

"""
    DBInterface.execute(conn::DBInterface.Connection, sql::AbstractString, [params]) => DBInterface.Cursor
    DBInterface.execute(stmt::DBInterface.Statement, [params]) => DBInterface.Cursor
    DBInterface.execute(f::Callable, conn::DBInterface.Connection, sql::AbstractString, [params])

Database packages should overload `DBInterface.execute` for a valid, prepared `DBInterface.Statement` subtype (the first method
signature is defined in DBInterface.jl using `DBInterface.prepare`), which takes an optional `params` argument, which should be
an indexable collection (`Vector` or `Tuple`) for positional parameters, or a `NamedTuple` for named parameters.
Alternatively, the parameters could be specified as keyword agruments of `DBInterface.execute`.

`DBInterface.execute` should return a valid `DBInterface.Cursor` object, which is any iterator of "rows",
which themselves must be property-accessible (i.e. implement `propertynames` and `getproperty` for value access by name),
and indexable (i.e. implement `length` and `getindex` for value access by index). These "result" objects do not need
to subtype `DBInterface.Cursor` explicitly as long as they satisfy the interface. For DDL/DML SQL statements, which typically
do not return results, an iterator is still expected to be returned that just iterates `nothing`, i.e. an "empty" iterator.

Note that `DBInterface.execute` returns ***a single*** `DBInterface.Cursor`, which represents a single resultset from the database.
For use-cases involving multiple result-sets from a single query, see `DBInterface.executemultiple`.

If function `f` is provided, `DBInterface.execute` will return the result of applying `f` to the `DBInterface.Cursor` object
and close the prepared statement upon exit.
"""
function execute end

execute(conn::Connection, sql::AbstractString, params) = execute(prepare(conn, sql), params)

function execute(f::Base.Callable, conn::Connection, sql::AbstractString, params)
    stmt = prepare(conn, sql)
    try
        cursor = execute(stmt, params)
        return f(cursor)
    finally
        close!(stmt)
    end
end

# keyarg versions
execute(stmt::Statement; kwargs...) = execute(stmt, kwargs.data)
execute(conn::Connection, sql::AbstractString; kwargs...) = execute(conn, sql, kwargs.data)
execute(f::Base.Callable, conn::Connection, sql::AbstractString; kwargs...) = execute(f, conn, sql, kwargs.data)

struct LazyIndex{T} <: AbstractVector{Any}
    x::T
    i::Int
end

Base.IndexStyle(::Type{<:LazyIndex}) = Base.IndexLinear()
Base.IteratorSize(::Type{<:LazyIndex}) = Base.HasLength()
Base.size(x::LazyIndex) = (length(x.x),)
Base.getindex(x::LazyIndex, i::Int) = x.x[i][x.i]

"""
    DBInterface.executemany(conn::DBInterface.Connection, sql::AbstractString, [params]) => Nothing
    DBInterface.executemany(stmt::DBInterface.Statement, [params]) => Nothing

Similar in usage to `DBInterface.execute`, but allows passing multiple sets of parameters to be executed in sequence.
`params`, like for `DBInterface.execute`, should be an indexable collection (`Vector` or `Tuple`) or `NamedTuple`, but instead
of a single scalar value per parameter, an indexable collection should be passed for each parameter. By default, each set of
parameters will be looped over and `DBInterface.execute` will be called for each. Note that no result sets or cursors are returned
for any execution, so the usage is mainly intended for bulk INSERT statements.
"""
function executemany(stmt::Statement, params)
    if !isempty(params)
        param = params[1]
        len = length(param)
        all(x -> length(x) == len, params) || throw(ParameterError("parameters provided to `DBInterface.executemany!` do not all have the same number of parameters"))
        for i = 1:len
            xargs = LazyIndex(params, i)
            execute(stmt, xargs)
        end
    else
        execute(stmt)
    end
    return
end

# keyarg version
executemany(conn::Connection, sql::AbstractString, params) = executemany(prepare(conn, sql), params)
executemany(conn::Connection, sql::AbstractString; kwargs...) = executemany(conn, sql, kwargs.data)

"""
    DBInterface.executemultiple(conn::DBInterface.Connection, sql::AbstractString, [params]) => Cursor-iterator
    DBInterface.executemultiple(stmt::DBInterface.Statement, [params]) => Cursor-iterator

Some databases allow returning multiple resultsets from a "single" query (typically semi-colon (`;`) separated statements, or from calling stored procedures).
This function takes the exact same arguments as `DBInterface.execute`, but instead of returning a single `Cursor`, it returns an iterator of `Cursor`s.
This function defines a generic fallback that just returns `(DBInterface.execute(stmt, params),)`, a length-1 tuple for a single `Cursor` resultset.
"""
function executemultiple end

executemultiple(stmt::Statement, params) = (execute(stmt, params),)
executemultiple(conn::Connection, sql::AbstractString, params) = executemultiple(prepare(conn, sql), params)

# keyarg version
executemultiple(stmt::Statement; kwargs...) = executemultiple(stmt, kwargs.data)
executemultiple(conn::Connection, sql::AbstractString; kwargs...) = executemultiple(conn, sql, kwargs.data)

"""
    DBInterface.lastrowid(x::Cursor) => Int

If supported by the specific database cursor, returns the last inserted row id after executing an INSERT statement.
"""
function lastrowid end

"""
    DBInterface.close!(x::Cursor) => Nothing

Immediately close a resultset cursor. Database packages should overload for the provided resultset `Cursor` object.
"""
close!(x::Cursor)

# exception handling
"Error for signaling that parameters are used inconsistently or incorrectly."
struct ParameterError <: Exception
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
