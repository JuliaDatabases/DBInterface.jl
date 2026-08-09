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
end

const prepare_count = Ref(0)

function DBInterface.prepare(connection::MockConnection, sql::AbstractString)
    prepare_count[] += 1
    return MockStatement(connection, String(sql))
end

DBInterface.getconnection(statement::MockStatement) = statement.connection

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

    changed_sql_statement = cached_statement(second_connection, "SELECT 2")
    @test changed_sql_statement.sql == "SELECT 2"
    @test changed_sql_statement !== second_statement

    @test other_cached_statement(second_connection, "SELECT 2") !== changed_sql_statement

    connections = [MockConnection(i) for i in 1:100]
    failures = fill(false, length(connections))
    Threads.@threads for i in eachindex(connections)
        sql = "SELECT $i"
        statement = cached_statement(connections[i], sql)
        failures[i] = statement.connection !== connections[i] || statement.sql != sql
    end
    @test !any(failures)
end
