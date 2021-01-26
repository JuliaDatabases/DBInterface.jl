# DBInterface.jl Documentation

```@contents
```
*DBInterface.jl* provides interface definitions to allow common database operations to be implemented consistently
across various database packages.

## Functions
```@docs
DBInterface.connect
DBInterface.prepare
DBInterface.@prepare
DBInterface.execute
DBInterface.executemany
DBInterface.executemultiple
DBInterface.close!
DBInterface.lastrowid
```

## Types

```@docs
DBInterface.Connection
DBInterface.Statement
DBInterface.Cursor
```
