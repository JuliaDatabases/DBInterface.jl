using DBInterface, Test

@test_throws DBInterface.NotImplementedError DBInterface.connect(Int64)