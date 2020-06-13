using DBInterface, Test

@test_throws MethodError DBInterface.connect(Int64)
