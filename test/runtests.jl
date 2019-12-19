using DBI, Test

@test_throws DBI.NotImplementedError DBI.connect(Int64)