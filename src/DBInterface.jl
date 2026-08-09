module DBInterface

export @sql_str;

"""
Declare the string as written in SQL.

The macro does not parse, escape, validate, or sanitize the string.
"""
macro sql_str(cmd)
    cmd
end

"Database packages should subtype `DBInterface.Connection` which represents a connection to a database"
abstract type Connection end

"""
    DBInterface.connect(DB, args...; kw...) => DBInterface.Connection
    DBInterface.connect(f::Callable, DB, args...; kw...)

Database packages should overload `DBInterface.connect` for a specific `DB` `DBInterface.Connection` subtype
that returns a valid, live database connection that can be queried against.

When `f` is provided, the connection is passed to `f`, closed upon exit, and the result of `f` is returned.
"""
function connect end

function connect(f::Base.Callable, DB, args...; kwargs...)
    conn = connect(DB, args...; kwargs...)
    try
        return f(conn)
    finally
        close!(conn)
    end
end

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
    DBInterface.getconnection(::DBInterface.Statement)

For a valid `DBInterface.Statement`, return the `DBInterface.Connection` the statement
is associated with. 
"""
function getconnection end

"""
    DBInterface.prepare(conn::DBInterface.Connection, sql::AbstractString) => DBInterface.Statement
    DBInterface.prepare(f::Function, sql::AbstractString) => DBInterface.Statement
    DBInterface.prepare(f::Callable, conn::DBInterface.Connection, sql::AbstractString; kw...)

Database packages should overload `DBInterface.prepare` for a specific `DBInterface.Connection` subtype, that validates and prepares
a SQL statement given as an `AbstractString` `sql` argument, and returns a `DBInterface.Statement` subtype. It is expected
that `DBInterface.Statement`s are only valid for the lifetime of the `DBInterface.Connection` object against which they are prepared.
For convenience, users may call `DBInterface.prepare(f::Function, sql)` which first calls `f()` to retrieve a valid `DBInterface.Connection`
before calling `DBInterface.prepare(conn, sql)`; this allows deferring connection retrieval and thus statement preparation until runtime,
which is often convenient when building applications.

When both `f` and `conn` are provided, the prepared statement is passed to `f`, closed upon exit, and the result of `f` is returned.
"""
function prepare end

prepare(f::Function, sql::AbstractString) = prepare(f(), sql)

function prepare(f::Base.Callable, conn::Connection, sql::AbstractString; kwargs...)
    stmt = prepare(conn, sql; kwargs...)
    try
        return f(stmt)
    finally
        close!(stmt)
    end
end

struct _PreparedStatementCacheEntry
    connection::Connection
    sql::String
    statement::Statement
end

const PREPARED_STMTS = Dict{Tuple{Module, Symbol}, _PreparedStatementCacheEntry}()
const PREPARED_STMTS_LOCK = ReentrantLock()

function _cached_prepare(getDB, sql::AbstractString, caller::Module, key::Symbol)
    connection = getDB()
    sql_string = String(sql)
    cache_key = (caller, key)
    lock(PREPARED_STMTS_LOCK)
    try
        entry = get(PREPARED_STMTS, cache_key, nothing)
        if entry !== nothing && entry.connection === connection && entry.sql == sql_string
            return entry.statement
        end
        statement = prepare(connection, sql_string)
        PREPARED_STMTS[cache_key] = _PreparedStatementCacheEntry(connection, sql_string, statement)
        return statement
    finally
        unlock(PREPARED_STMTS_LOCK)
    end
end

"""
    DBInterface.@prepare f sql

Takes a zero-argument `DBInterface.Connection`-retrieval function `f` and SQL statement `sql` and returns a prepared statement via `DBInterface.prepare`.
Each call site caches one statement. The cached statement is reused while both the connection object and SQL text remain unchanged.
The cache is synchronized, but it does not make a connection or statement safe for concurrent use.
"""
macro prepare(getDB, sql)
    key = gensym()
    return :(DBInterface._cached_prepare($(esc(getDB)), $(esc(sql)), $(QuoteNode(__module__)), $(QuoteNode(key))))
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
    DBInterface.execute(f::Callable, stmt::DBInterface.Statement, [params])

Database packages should overload `DBInterface.execute` for a valid, prepared `DBInterface.Statement` subtype (the connection
signature is defined in DBInterface.jl using `DBInterface.prepare`), which takes an optional `params` argument. Parameters should be
an indexable collection (`AbstractVector` or `Tuple`) for positional parameters, or a `NamedTuple` or `AbstractDict` for named parameters.
Alternatively, the parameters could be specified as keyword arguments of `DBInterface.execute`.

Placeholder syntax and named-parameter support are driver-specific. Each placeholder normally binds one scalar value. DBInterface
does not parse or sanitize SQL, and bound parameters cannot replace identifiers, keywords, or other SQL fragments.

`DBInterface.execute` should return a valid `DBInterface.Cursor` object, which is any iterator of "rows",
which themselves must be property-accessible (i.e. implement `propertynames` and `getproperty` for value access by name),
and indexable (i.e. implement `length` and `getindex` for value access by index). These "result" objects do not need
to subtype `DBInterface.Cursor` explicitly as long as they satisfy the interface and implement `DBInterface.close!`. For DDL/DML
SQL statements, which typically do not return results, an empty iterator is still expected.

Note that `DBInterface.execute` returns **a single** `DBInterface.Cursor`, which represents a single resultset from the database.
For use-cases involving multiple result-sets from a single query, see `DBInterface.executemultiple`.

If function `f` is provided, `DBInterface.execute` returns the result of applying `f` to the cursor and closes the cursor upon exit.
The connection form also closes the statement that it prepares internally.
"""
function execute end

execute(conn::Connection, sql::AbstractString, params) = execute(prepare(conn, sql), params)

function execute(f::Base.Callable, stmt::Statement, params)
    cursor = execute(stmt, params)
    try
       return f(cursor)
    finally
        close!(cursor)
    end
end

function execute(f::Base.Callable, conn::Connection, sql::AbstractString, params)
    stmt = prepare(conn, sql)
    try
        return execute(f, stmt, params)
    finally
        close!(stmt)
    end
end

# keyarg versions
execute(stmt::Statement; kwargs...) = execute(stmt, values(kwargs))
execute(conn::Connection, sql::AbstractString; kwargs...) = execute(conn, sql, values(kwargs))
execute(f::Base.Callable, conn::Connection, sql::AbstractString; kwargs...) = execute(f, conn, sql, values(kwargs))
execute(f::Base.Callable, stmt::Statement; kwargs...) = execute(f, stmt, values(kwargs))

"""
    DBInterface.transaction(f, conn::DBInterface.Connection)

Open a transaction against a database connection `conn`, execute a closure `f`,
then commit the transaction after executing the closure. The default definition
executes `BEGIN TRANSACTION`, `COMMIT`, and, after an error, `ROLLBACK`. Database
packages should overload this method when those commands do not match the database's
transaction behavior. `DBInterface.executemany` uses this method because a transaction
often makes repeated statements much faster. If both the transaction and its rollback
fail, a `CompositeException` reports both errors, with the original error first.
"""
function transaction(f, conn::Connection)
    _execute_and_close(conn, "BEGIN TRANSACTION;")
    try
        ret = f()
        _execute_and_close(conn, "COMMIT;")
        return ret
    catch transaction_error
        transaction_backtrace = catch_backtrace()
        try
            _execute_and_close(conn, "ROLLBACK;")
        catch rollback_error
            rollback_backtrace = catch_backtrace()
            throw(CompositeException([
                CapturedException(transaction_error, transaction_backtrace),
                CapturedException(rollback_error, rollback_backtrace),
            ]))
        end
        rethrow()
    end
end

struct LazyIndex{T} <: AbstractVector{Any}
    x::T
    i::Int
end

Base.IndexStyle(::Type{<:LazyIndex}) = Base.IndexLinear()
Base.IteratorSize(::Type{<:LazyIndex}) = Base.HasLength()
Base.size(x::LazyIndex) = (length(x.x),)
Base.getindex(x::LazyIndex, i::Int) = x.x[i][x.i]

struct LazyNamedIndex{T, K, V} <: AbstractDict{K, V}
    x::T
    i::Int
end

LazyNamedIndex(x::T, i::Int) where {T <: AbstractDict} =
    LazyNamedIndex{T, Base.keytype(T), eltype(Base.valtype(T))}(x, i)

Base.length(x::LazyNamedIndex) = length(x.x)
Base.getindex(x::LazyNamedIndex, key) = x.x[key][x.i]

function Base.iterate(x::LazyNamedIndex, state...)
    result = iterate(x.x, state...)
    result === nothing && return nothing
    pair, next_state = result
    return (pair.first => pair.second[x.i], next_state)
end

_parameter_collections(params::PositionalStatementParams) = params
_parameter_collections(params::NamedStatementParams) = values(params)

_parameter_row(params::PositionalStatementParams, i::Int) = LazyIndex(params, i)
_parameter_row(params::NamedTuple, i::Int) = LazyIndex(values(params), i)
_parameter_row(params::AbstractDict, i::Int) = LazyNamedIndex(params, i)

function _execute_and_close(stmt::Statement, params)
    cursor = execute(stmt, params)
    applicable(close!, cursor) && close!(cursor)
    return
end

function _execute_and_close(stmt::Statement)
    cursor = execute(stmt)
    applicable(close!, cursor) && close!(cursor)
    return
end

function _execute_and_close(conn::Connection, sql::AbstractString)
    stmt = prepare(conn, sql)
    try
        return _execute_and_close(stmt)
    finally
        close!(stmt)
    end
end

"""
    DBInterface.executemany(conn::DBInterface.Connection, sql::AbstractString, [params]) => Nothing
    DBInterface.executemany(stmt::DBInterface.Statement, [params]) => Nothing

Similar in usage to `DBInterface.execute`, but allows passing multiple sets of parameters to be executed in sequence.
`params`, like for `DBInterface.execute`, should be an `AbstractVector`, `Tuple`, `NamedTuple`, or `AbstractDict`, but instead
of a single scalar value per parameter, an indexable collection should be passed for each parameter. By default, each set of
parameters will be looped over and `DBInterface.execute` will be called for each. Note that no result sets or cursors are returned
for any execution, so the usage is mainly intended for bulk INSERT statements. For compatibility, a `NamedTuple` or keyword batch
is passed to each execution positionally in field order. Use an `AbstractDict` batch when each execution must retain parameter names.
"""
function executemany(stmt::Statement, params)
    param_collections = _parameter_collections(params)
    if !isempty(param_collections)
        param = first(param_collections)
        len = length(param)
        all(x -> length(x) == len, param_collections) || throw(ParameterError("parameter collections provided to `DBInterface.executemany` must have equal lengths"))
        len == 0 && return
        transaction(getconnection(stmt)) do
            for i = 1:len
                _execute_and_close(stmt, _parameter_row(params, i))
            end
        end
    else
        _execute_and_close(stmt, params)
    end
    return
end

# keyarg version
function executemany(conn::Connection, sql::AbstractString, params)
    stmt = prepare(conn, sql)
    try
        return executemany(stmt, params)
    finally
        close!(stmt)
    end
end

executemany(conn::Connection, sql::AbstractString; kwargs...) = executemany(conn, sql, values(kwargs))

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
executemultiple(stmt::Statement; kwargs...) = executemultiple(stmt, values(kwargs))
executemultiple(conn::Connection, sql::AbstractString; kwargs...) = executemultiple(conn, sql, values(kwargs))

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

Base.showerror(io::IO, error::ParameterError) = print(io, error.msg)
Base.showerror(io::IO, error::Error) = print(io, error.msg)

end # module
