module DBI
    using DataArrays
    using DataFrames

    export columninfo,
           disconnect,
           errcode,
           errstring,
           execute,
           executed,
           fetchall,
           fetchdf,
           fetchrow,
           finish,
           lastinsertid,
           prepare,
           sqlescape,
           sql2jltype,
           tableinfo

    abstract DatabaseSystem
    abstract DatabaseHandle
    abstract StatementHandle

    immutable DatabaseColumn
        name::UTF8String
        datatype::DataType
        length::Int
        collation::UTF8String
        nullable::Bool
        primarykey::Bool
        autoincrement::Bool
    end
    immutable DatabaseTable
        name::UTF8String
        columns::Vector{DatabaseColumn}
    end

    function columninfo(db::DatabaseHandle, table::String, column::String)
        error("DBI API not fully implemented")
    end

    function Base.connect(db::DatabaseSystem, args::Any...)
        error("DBI API not fully implemented")
    end

    function disconnect(db::DatabaseHandle)
        error("DBI API not fully implemented")
    end

    # Native error code
    function errcode(db::DatabaseHandle)
        error("DBI API not fully implemented")
    end

    # TODO: Need this? Redundancy sucks
    # errcode(stmt::StatementHandle) = errcode(stmt.db)

    # Native error string
    function errstring(db::DatabaseHandle)
        error("DBI API not fully implemented")
    end

    # TODO: Need this? Redundancy sucks
    # errstring(stmt::StatementHandle) = errstring(stmt.db)

    function execute(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function executed(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function fetchall(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function fetchdf(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function fetchrow(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function finish(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function lastinsertid(db::DatabaseHandle)
        error("DBI API not fully implemented")
    end

    function prepare(db::DatabaseHandle, sql::String)
        error("DBI API not fully implemented")
    end

    function Base.run(db::DatabaseHandle, sql::String)
        stmt = prepare(db, sql)
        execute(stmt)
        finish(stmt)
        return
    end

    function Base.show(io::IO, col::DatabaseColumn)
        @printf io "Name: `%s`\n" col.name
        @printf io "Type: %s\n" col.datatype
        @printf io "Length: %d\n" col.length
        @printf io "Collation: %s\n" col.collation
        @printf io "Is Nullable: %s\n" col.nullable
        @printf io "Is Primary Key: %s\n" col.primarykey
        @printf io "Is Autoincrement: %s\n" col.autoincrement
        return
    end

    function sqlescape(sql::String)
        error("Not yet implemented")
    end

    function sql2jltype(t::String)
        if t == "INT"
            return Int, 0
        elseif t == "REAL"
            return Float64, 0
        elseif ismatch(r"VARCHAR\((\d+)\)", t)
            m = match(r"VARCHAR\((\d+)\)", t)
            return UTF8String, int(m.captures[1])
        elseif t == "TEXT"
            return UTF8String, -1
        elseif t == "BLOB"
            return Vector{Uint8}, -1
        else
            error("Need to implement sql2jltype for $t")
        end
    end

    function tableinfo(db::DatabaseHandle, table::String)
        error("DBI API not fully implemented")
    end

    function Base.select(db::DatabaseHandle, sql::String)
        stmt = prepare(db, sql)
        execute(stmt)
        df = fetchdf(stmt)
        finish(stmt)
        return df
    end
end
