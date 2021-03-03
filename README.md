# DBInterface.jl

### Purpose
DBInterface.jl provides interface definitions to allow common database operations to be implemented consistently
across various database packages.

### For Users
To use DBInterface.jl, select an implementing database package, then utilize the consistent DBInterface.jl interface methods:
```julia
conn = DBInterface.connect(T, args...; kw...) # create a connection to a specific database T; required parameters are database-specific

stmt = DBInterface.prepare(conn, sql) # prepare a sql statement against the connection; returns a statement object

results = DBInterface.execute(stmt) # execute a prepared statement; returns an iterator of rows (property-accessible & indexable)

rowid = DBInterface.lastrowid(results) # get the last row id of an INSERT statement, as supported by the database

# example of using a query resultset
for row in results
    @show propertynames(row) # see possible column names of row results
    row.col1 # access the value of a column named `col1`
    row[1] # access the first column in the row results
end

# results also implicitly satisfy the Tables.jl `Tables.rows` inteface, so any compatible sink can ingest results
df = DataFrame(results)
CSV.write("results.csv", results)

results = DBInterface.execute(conn, sql) # convenience method if statement preparation/re-use isn't needed

stmt = DBInterface.prepare(conn, "INSERT INTO test_table VALUES(?, ?)") # prepare a statement with positional parameters

DBInterface.execute(stmt, [1, 3.14]) # execute the prepared INSERT statement, passing 1 and 3.14 as positional parameters

stmt = DBInterface.prepare(conn, "INSERT INTO test_table VALUES(:col1, :col2)") # prepare a statement with named parameters

DBInterface.execute(stmt, (col1=1, col2=3.14)) # execute the prepared INSERT statement, with 1 and 3.14 as named parameters

DBInterface.executemany(stmt, (col1=[1,2,3,4,5], col2=[3.14, 1.23, 2.34 3.45, 4.56])) # execute the prepared statement multiple times for each set of named parameters; each named parameter must be an indexable collection

results = DBInterface.executemultiple(conn, sql) # where sql is a query that returns multiple resultsets

# first iterate through resultsets
for result in results
    # for each resultset, we can iterate through resultset rows
    for row in result
        @show propertynames(row)
        row.col1
        row[1]
    end
end

DBInterface.close!(stmt) # close the prepared statement
DBInterface.close!(conn) # close connection
```

### For Database Package Developers
See the [documentation](https://juliadatabases.org/DBInterface.jl/latest/) for expanded details on required interface methods.  