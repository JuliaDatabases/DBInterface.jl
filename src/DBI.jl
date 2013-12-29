module DBI
    export disconnect,
           execute,
           fetchall,
           fetchrow,
           finish,
           prepare,
           sqlescape

    abstract DatabaseSystem
    abstract DatabaseHandle
    abstract StatementHandle
    abstract ResultSet

    function Base.connect(db::DatabaseSystem, args::Any...)
        error("DBI API not fully implemented")
    end

    function disconnect(db::DatabaseHandle)
        error("DBI API not fully implemented")
    end

    function execute(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function fetchall(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function fetchrow(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function finish(stmt::StatementHandle)
        error("DBI API not fully implemented")
    end

    function prepare(db::DatabaseHandle, sql::String)
        error("DBI API not fully implemented")
    end

    function Base.run(db::DatabaseHandle, sql::String)
        error("DBI API not fully implemented")
    end

    function sqlescape(sql::String)
        error("Not yet implemented")
    end
end
