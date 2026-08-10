using DBInterface, Test

@test_throws MethodError DBInterface.connect(Int64)

# test @sql_str macro (does nothing)
@test sql"SELECT * FROM MyTable" == "SELECT * FROM MyTable"

mutable struct MockConnection <: DBInterface.Connection
    id::Int
end

mutable struct MockStatement <: DBInterface.Statement
    connection::MockConnection
    sql::String
    closed::Bool
end

const prepare_count = Ref(0)

function DBInterface.prepare(connection::MockConnection, sql::AbstractString)
    prepare_count[] += 1
    return MockStatement(connection, String(sql), false)
end

DBInterface.getconnection(statement::MockStatement) = statement.connection
DBInterface.close!(statement::MockStatement) = statement.closed = true

cached_statement(connection, sql) = DBInterface.@prepare(() -> connection, sql)
other_cached_statement(connection, sql) = DBInterface.@prepare(() -> connection, sql)

@testset "@prepare" begin
    prepare_count[] = 0
    first_connection = MockConnection(1)
    second_connection = MockConnection(2)

    first_statement = cached_statement(first_connection, "SELECT 1")
    @test first_statement === cached_statement(first_connection, "SELECT 1")
    @test prepare_count[] == 1

    second_statement = cached_statement(second_connection, "SELECT 1")
    @test second_statement.connection === second_connection
    @test second_statement !== first_statement
    @test !first_statement.closed

    changed_sql_statement = cached_statement(second_connection, "SELECT 2")
    @test changed_sql_statement.sql == "SELECT 2"
    @test changed_sql_statement !== second_statement
    @test second_statement.closed

    @test cached_statement(first_connection, "SELECT 1") === first_statement

    @test other_cached_statement(second_connection, "SELECT 2") !== changed_sql_statement

    connections = [MockConnection(i) for i in 1:100]
    failures = fill(false, length(connections))
    Threads.@threads for i in eachindex(connections)
        sql = "SELECT $i"
        statement = cached_statement(connections[i], sql)
        failures[i] = statement.connection !== connections[i] || statement.sql != sql
    end
    @test !any(failures)

    pooled_prepare_count = prepare_count[]
    Threads.@threads for i in eachindex(connections)
        statement = cached_statement(connections[i], "SELECT $i")
        failures[i] = statement.connection !== connections[i] || statement.sql != "SELECT $i"
    end
    @test !any(failures)
    @test prepare_count[] == pooled_prepare_count
end

mutable struct ExecutionConnection <: DBInterface.Connection
    statements::Vector{Any}
end

ExecutionConnection() = ExecutionConnection(Any[])

const execution_transaction_count = Ref(0)

mutable struct ExecutionStatement <: DBInterface.Statement
    connection::ExecutionConnection
    sql::String
    executions::Vector{Any}
    cursors::Vector{Any}
    closed::Bool
end

mutable struct ExecutionCursor <: DBInterface.Cursor
    closed::Bool
end

function DBInterface.prepare(connection::ExecutionConnection, sql::AbstractString)
    statement = ExecutionStatement(connection, String(sql), Any[], Any[], false)
    push!(connection.statements, statement)
    return statement
end

DBInterface.getconnection(statement::ExecutionStatement) = statement.connection
function DBInterface.transaction(f, ::ExecutionConnection)
    execution_transaction_count[] += 1
    return f()
end
DBInterface.close!(statement::ExecutionStatement) = statement.closed = true
DBInterface.close!(cursor::ExecutionCursor) = cursor.closed = true

function DBInterface.execute(statement::ExecutionStatement, params)
    push!(statement.executions, params)
    statement.sql == "fail" && length(statement.executions) == 2 && error("execution failed")
    statement.sql == "nothing" && return nothing
    cursor = ExecutionCursor(false)
    push!(statement.cursors, cursor)
    return cursor
end

@testset "executemany" begin
    connection = ExecutionConnection()

    positional_statement = DBInterface.prepare(connection, "positional")
    DBInterface.executemany(positional_statement, ([1, 2], [3.0, 4.0]))
    @test collect.(positional_statement.executions) == [[1, 3.0], [2, 4.0]]
    @test all(cursor -> cursor.closed, positional_statement.cursors)

    named_statement = DBInterface.prepare(connection, "named")
    DBInterface.executemany(named_statement, (id=[1, 2], name=["one", "two"]))
    @test collect.(named_statement.executions) == [[1, "one"], [2, "two"]]
    @test all(params -> params isa AbstractVector, named_statement.executions)
    @test all(cursor -> cursor.closed, named_statement.cursors)

    dictionary_statement = DBInterface.prepare(connection, "dictionary")
    DBInterface.executemany(dictionary_statement, Dict(:id => [1, 2], :name => ["one", "two"]))
    @test Dict.(dictionary_statement.executions) == [
        Dict(:id => 1, :name => "one"),
        Dict(:id => 2, :name => "two"),
    ]
    @test all(params -> params isa AbstractDict, dictionary_statement.executions)

    invalid_statement = DBInterface.prepare(connection, "invalid")
    @test_throws DBInterface.ParameterError DBInterface.executemany(
        invalid_statement,
        (id=[1, 2], name=["one"]),
    )
    @test isempty(invalid_statement.executions)

    DBInterface.executemany(connection, "managed", (id=[1, 2],))
    managed_statement = connection.statements[end]
    @test managed_statement.closed
    @test collect.(managed_statement.executions) == [[1], [2]]

    @test_throws ErrorException DBInterface.executemany(connection, "fail", (id=[1, 2],))
    failed_statement = connection.statements[end]
    @test failed_statement.closed
    @test failed_statement.cursors[1].closed

    nothing_statement = DBInterface.prepare(connection, "nothing")
    DBInterface.executemany(nothing_statement, (id=[1, 2],))
    @test collect.(nothing_statement.executions) == [[1], [2]]

    execution_transaction_count[] = 0
    empty_batch_statement = DBInterface.prepare(connection, "empty batch")
    DBInterface.executemany(empty_batch_statement, (id=Int[],))
    @test isempty(empty_batch_statement.executions)
    @test execution_transaction_count[] == 0

    empty_statement = DBInterface.prepare(connection, "empty")
    DBInterface.executemany(empty_statement, ())
    @test empty_statement.executions == [()]
    @test empty_statement.cursors[1].closed
end

mutable struct TransactionConnection <: DBInterface.Connection
    commands::Vector{String}
    statements::Vector{Any}
    fail_on::Union{Nothing, String}
end

TransactionConnection(; fail_on=nothing) = TransactionConnection(String[], Any[], fail_on)

mutable struct TransactionStatement <: DBInterface.Statement
    connection::TransactionConnection
    sql::String
    closed::Bool
end

mutable struct TransactionCursor <: DBInterface.Cursor
    closed::Bool
end

function DBInterface.prepare(connection::TransactionConnection, sql::AbstractString)
    statement = TransactionStatement(connection, String(sql), false)
    push!(connection.statements, statement)
    return statement
end

DBInterface.getconnection(statement::TransactionStatement) = statement.connection
DBInterface.close!(statement::TransactionStatement) = statement.closed = true
DBInterface.close!(cursor::TransactionCursor) = cursor.closed = true

function DBInterface.execute(statement::TransactionStatement, params)
    connection = statement.connection
    push!(connection.commands, statement.sql)
    connection.fail_on == statement.sql && error("$(statement.sql) failed")
    return TransactionCursor(false)
end

@testset "transaction" begin
    connection = TransactionConnection()
    @test DBInterface.transaction(() -> 42, connection) == 42
    @test connection.commands == ["BEGIN TRANSACTION;", "COMMIT;"]
    @test all(statement -> statement.closed, connection.statements)

    body_connection = TransactionConnection()
    body_error = ErrorException("body failed")
    caught_error = try
        DBInterface.transaction(body_connection) do
            throw(body_error)
        end
    catch error
        error
    end
    @test caught_error === body_error
    @test body_connection.commands == ["BEGIN TRANSACTION;", "ROLLBACK;"]
    @test all(statement -> statement.closed, body_connection.statements)

    rollback_connection = TransactionConnection(fail_on="ROLLBACK;")
    rollback_body_error = ErrorException("body failed before rollback")
    rollback_caught_error = try
        DBInterface.transaction(rollback_connection) do
            throw(rollback_body_error)
        end
    catch error
        error
    end
    @test rollback_caught_error isa CompositeException
    @test rollback_caught_error.exceptions[1].ex === rollback_body_error
    @test occursin("ROLLBACK; failed", sprint(showerror, rollback_caught_error.exceptions[2].ex))
    @test rollback_connection.commands == ["BEGIN TRANSACTION;", "ROLLBACK;"]
    @test all(statement -> statement.closed, rollback_connection.statements)

    commit_connection = TransactionConnection(fail_on="COMMIT;")
    commit_error = try
        DBInterface.transaction(() -> nothing, commit_connection)
    catch error
        error
    end
    @test occursin("COMMIT; failed", sprint(showerror, commit_error))
    @test commit_connection.commands == ["BEGIN TRANSACTION;", "COMMIT;", "ROLLBACK;"]
end

struct MockDatabase end

mutable struct ScopedConnection <: DBInterface.Connection
    closed::Bool
end

const scoped_connections = ScopedConnection[]

function DBInterface.connect(::Type{MockDatabase}; option=false)
    @test option
    connection = ScopedConnection(false)
    push!(scoped_connections, connection)
    return connection
end

DBInterface.close!(connection::ScopedConnection) = connection.closed = true

mutable struct ScopedStatement <: DBInterface.Statement
    connection::ScopedConnection
    sql::String
    option::Bool
    closed::Bool
end

function DBInterface.prepare(connection::ScopedConnection, sql::AbstractString; option=false)
    return ScopedStatement(connection, String(sql), option, false)
end

DBInterface.close!(statement::ScopedStatement) = statement.closed = true

@testset "scoped resources" begin
    empty!(scoped_connections)
    result = DBInterface.connect(MockDatabase; option=true) do connection
        @test !connection.closed
        return 42
    end
    @test result == 42
    @test scoped_connections[1].closed

    connection_error = ErrorException("connection body failed")
    caught_connection_error = try
        DBInterface.connect(MockDatabase; option=true) do connection
            throw(connection_error)
        end
    catch error
        error
    end
    @test caught_connection_error === connection_error
    @test scoped_connections[2].closed

    connection = ScopedConnection(false)
    statement = Ref{ScopedStatement}()
    statement_result = DBInterface.prepare(connection, "SELECT 1"; option=true) do prepared
        statement[] = prepared
        @test !prepared.closed
        @test prepared.option
        return prepared.sql
    end
    @test statement_result == "SELECT 1"
    @test statement[].closed

    statement_error = ErrorException("statement body failed")
    caught_statement_error = try
        DBInterface.prepare(connection, "SELECT 2"; option=true) do prepared
            statement[] = prepared
            throw(statement_error)
        end
    catch error
        error
    end
    @test caught_statement_error === statement_error
    @test statement[].closed
end

@testset "error display" begin
    @test sprint(showerror, DBInterface.ParameterError("invalid parameters")) == "invalid parameters"
    @test sprint(showerror, DBInterface.Error("database error")) == "database error"
end
