# MS SQL Server Setup
A repo containing the core MSSQL Server stored procs, functions, tables, and views that I use for all databases.

# Using SPROC_GenerateShadowTable

After executing the script that generates SPROC_GenerateShadowTable, usage is simple. This should work on any MSSQL database table.

This stored proc does a couple things:

- It creates a corresponding "shadow" table for auditing purposes. All actions on the 'source' table will be inserted into the corresponding shadow table (inserts, updates, deletes). Shadow tables are named the same as the target table but with '_shadow_' proceeding the target table. So for example if you create a shadow table for Users then the corresponding shadow table will be named _shadow_Users.

- It creates a simple trigger on the source table so that inserts, updates, and deletes are automatically inserted into the related shadow table, providing a full audit trail.

There are three parameters, two of them are optional.

@TableName - The target table you want to create a shadow table for.
@Owner - The table owner (optional, defaults to 'dbo').
@DropAuditTable - if set to 1 then it will drop and regenerate the shadow table (optional, defaults to 0).

Usage is very simple. If, for example, you have a Users table that you want to start auditing then you simply have to call:

EXEC SPROC_GenerateShadowTable 'Users'

Now any insert, update, or delete actions will be inserted into the corresponding _shadow_Users table.
