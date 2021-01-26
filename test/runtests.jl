using DBInterface, Test

@test_throws MethodError DBInterface.connect(Int64)

# test @sql_str macro (does nothing)
@test sql"SELECT * FROM MyTable" == "SELECT * FROM MyTable"
