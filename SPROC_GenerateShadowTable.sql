-- Shadow tables are used for audit tracking. They are basically a shadow copy of the target table
-- containing a full audit trail.

IF OBJECT_ID('SPROC_GenerateShadowTable', 'P') IS NOT NULL DROP PROCEDURE [SPROC_GenerateShadowTable]
GO
CREATE PROCEDURE [dbo].[SPROC_GenerateShadowTable]
	@TableName varchar(128),
	@Owner varchar(128) = 'dbo',
	@DropAuditTable bit = 0
AS
BEGIN
	IF NOT EXISTS (SELECT * FROM dbo.sysobjects WHERE id = object_id(N'[' + @Owner + '].[' + @TableName + ']') and OBJECTPROPERTY(id, N'IsUserTable') = 1)
	BEGIN
		PRINT 'ERROR: Table does not exist'
		RETURN
	END

	IF (EXISTS (SELECT * FROM dbo.sysobjects WHERE id = OBJECT_ID(N'[' + @Owner + '].[_shadow_' + @TableName + ']') and OBJECTPROPERTY(id, N'IsUserTable') = 1) AND @DropAuditTable = 1)
	BEGIN
		PRINT 'Dropping audit table [' + @Owner + '].[_shadow_' + @TableName + ']'
		EXEC ('DROP TABLE _shadow_' + @TableName)
	END

	DECLARE TableColumns CURSOR READ_ONLY
	FOR SELECT b.name, c.name as TypeName, b.length, b.isnullable, b.collation, b.xprec, b.xscale
		FROM sysobjects a 
			INNER JOIN syscolumns b on a.id = b.id 
			INNER JOIN systypes c on b.xtype = c.xtype and c.name <> 'sysname' 
		WHERE a.id = object_id(N'[' + @Owner + '].[' + @TableName + ']') 
			AND OBJECTPROPERTY(a.id, N'IsUserTable') = 1 
		ORDER BY b.colId

	OPEN TableColumns

	DECLARE @ColumnName varchar(128)
	DECLARE @ColumnType varchar(128)
	DECLARE @ColumnLength smallint
	DECLARE @ColumnNullable int
	DECLARE @ColumnCollation sysname
	DECLARE @ColumnPrecision tinyint
	DECLARE @ColumnScale tinyint
	DECLARE @CreateStatement varchar(8000)
	DECLARE @ListOfFields varchar(2000)
	SET @ListOfFields = ''

	IF EXISTS (SELECT * FROM dbo.sysobjects WHERE id = object_id(N'[' + @Owner + '].[_shadow_' + @TableName + ']') and OBJECTPROPERTY(id, N'IsUserTable') = 1)
	BEGIN
		PRINT 'Table already exists. Only triggers will be updated.'

		FETCH NEXT FROM TableColumns
		INTO @ColumnName, @ColumnType, @ColumnLength, @ColumnNullable, @ColumnCollation, @ColumnPrecision, @ColumnScale
		
		WHILE @@FETCH_STATUS = 0
		BEGIN
			DECLARE @columnWidthText VARCHAR(MAX) SET @columnWidthText = ''

			IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE [Name] = @ColumnName AND OBJECT_ID = OBJECT_ID(@Owner + '._shadow_' + @TableName)) BEGIN
				SET @columnWidthText = CASE WHEN @ColumnType IN ('uniqueidentifier', 'int', 'datetime') THEN ' ' ELSE ' (' + CAST(@ColumnLength AS VARCHAR(MAX)) + ')' END
				PRINT @columnWidthText
				EXEC ('ALTER TABLE ' + @owner + '.[_shadow_'+ @TableName + '] ADD ' + @ColumnName + ' ' + @ColumnType + @columnWidthText+ ' NULL')
			END ELSE BEGIN			
				SET @columnWidthText = CASE WHEN CAST(@ColumnType AS VARCHAR(100)) IN ('uniqueidentifier', 'int', 'datetime') THEN ' ' ELSE ' (' + CAST(@ColumnLength AS VARCHAR(MAX)) + ')' END
				PRINT  CAST(@ColumnLength AS VARCHAR(MAX)) + 'llsd'
				EXEC ('ALTER TABLE ' + @owner + '.[_shadow_'+ @TableName + '] ALTER COLUMN ' + @ColumnName + ' ' + @ColumnType + @columnWidthText + ' NULL')
			END

			IF (@ColumnType <> 'TEXT' and @ColumnType <> 'NTEXT' and @ColumnType <> 'IMAGE' and @ColumnType <> 'TIMESTAMP')
				SET @ListOfFields = @ListOfFields + @ColumnName + ','

			FETCH NEXT FROM TableColumns
			INTO @ColumnName, @ColumnType, @ColumnLength, @ColumnNullable, @ColumnCollation, @ColumnPrecision, @ColumnScale
		END
	END
	ELSE
	BEGIN
		SET @CreateStatement = 'CREATE TABLE [' + @Owner + '].[_shadow_' + @TableName + '] ('
		SET @CreateStatement = @CreateStatement + '[AuditId] [bigint] IDENTITY (1, 1) NOT NULL,'

		FETCH NEXT FROM TableColumns
		INTO @ColumnName, @ColumnType, @ColumnLength, @ColumnNullable, @ColumnCollation, @ColumnPrecision, @ColumnScale
		
		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF (@ColumnType <> 'text' and @ColumnType <> 'NTEXT' and @ColumnType <> 'IMAGE' and @ColumnType <> 'TIMESTAMP')
			BEGIN
				SET @ListOfFields = @ListOfFields + @ColumnName + ','		
				SET @CreateStatement = @CreateStatement + '[' + @ColumnName + '] [' + @ColumnType + '] '			
				IF @ColumnType in ('BINARY', 'CHAR', 'NCHAR', 'NVARCHAR', 'VARBINARY', 'VARCHAR')
				BEGIN
					IF (@ColumnLength = -1)
						Set @CreateStatement = @CreateStatement + '(MAX) '	 	
					ELSE
						SET @CreateStatement = @CreateStatement + '(' + cast(@ColumnLength AS VARCHAR(10)) + ') '	 	
				END
		
				IF @ColumnType in ('DECIMAL', 'NUMERIC')
					SET @CreateStatement = @CreateStatement + '(' + cast(@ColumnPrecision AS VARCHAR(10)) + ',' + cast(@ColumnScale AS VARCHAR(10)) + ') '	 			
				IF @ColumnType in ('CHAR', 'NCHAR', 'NVARCHAR', 'VARCHAR', 'TEXT', 'NTEXT')
					SET @CreateStatement = @CreateStatement + 'COLLATE ' + @ColumnCollation + ' '			 	
		
				SET @CreateStatement = @CreateStatement + 'NULL, '	 	
			END

			FETCH NEXT FROM TableColumns
			INTO @ColumnName, @ColumnType, @ColumnLength, @ColumnNullable, @ColumnCollation, @ColumnPrecision, @ColumnScale
		END
		
		SET @CreateStatement = @CreateStatement + '[AuditAction] [CHAR] (1) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL ,'
		SET @CreateStatement = @CreateStatement + '[AuditDate] [DATETIME] NOT NULL ,'
		SET @CreateStatement = @CreateStatement + '[AuditUser] [VARCHAR] (50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,'
		SET @CreateStatement = @CreateStatement + '[AuditApp] [VARCHAR](128) COLLATE SQL_Latin1_General_CP1_CI_AS NULL)' 

		PRINT 'Creating audit table [' + @Owner + '].[_shadow_' + @TableName + ']'
		-- PRINT @CreateStatement
		EXEC (@CreateStatement)

		SET @CreateStatement = 'ALTER TABLE [' + @Owner + '].[_shadow_' + @TableName + '] ADD '
		SET @CreateStatement = @CreateStatement + 'CONSTRAINT [DF__shadow_' + @TableName + '_AuditDate] DEFAULT (GETDATE()) FOR [AuditDate],'
		SET @CreateStatement = @CreateStatement + 'CONSTRAINT [DF__shadow_' + @TableName + '_AuditUser] DEFAULT (suser_sname()) FOR [AuditUser],CONSTRAINT [PK__shadow_' + @TableName + '] PRIMARY KEY  CLUSTERED '
		SET @CreateStatement = @CreateStatement + '([AuditId])  ON [PRIMARY], '
		SET @CreateStatement = @CreateStatement + 'CONSTRAINT [DF__shadow_' + @TableName + '_AuditApp]  DEFAULT (''App=('' + RTRIM(ISNULL(app_name(),'''')) + '') '') FOR [AuditApp]'

		--PRINT '/r/n----------------------------------------------------------/r/n'


		--PRINT @CreateStatement

		EXEC (@CreateStatement)

	END

	CLOSE TableColumns
	DEALLOCATE TableColumns

	PRINT 'Dropping triggers'
	IF EXISTS (SELECT * FROM dbo.sysobjects WHERE id = object_id(N'[' + @Owner + '].[tr_' + @TableName + '_Insert]') and OBJECTPROPERTY(id, N'IsTrigger') = 1) 
		EXEC ('DROP TRIGGER [' + @Owner + '].[tr_' + @TableName + '_Insert]')

	IF EXISTS (SELECT * FROM dbo.sysobjects WHERE id = object_id(N'[' + @Owner + '].[tr_' + @TableName + '_Update]') and OBJECTPROPERTY(id, N'IsTrigger') = 1) 
		EXEC ('DROP TRIGGER [' + @Owner + '].[tr_' + @TableName + '_Update]')

	IF EXISTS (SELECT * FROM dbo.sysobjects WHERE id = object_id(N'[' + @Owner + '].[tr_' + @TableName + '_Delete]') and OBJECTPROPERTY(id, N'IsTrigger') = 1) 
		EXEC ('DROP TRIGGER [' + @Owner + '].[tr_' + @TableName + '_Delete]')

	PRINT 'Creating triggers' 
	EXEC ('CREATE TRIGGER tr_' + @TableName + '_Insert ON ' + @Owner + '.[' + @TableName + '] FOR INSERT AS INSERT INTO _shadow_' + @TableName + '(' +  @ListOfFields + 'AuditAction) SELECT ' + @ListOfFields + '''I'' FROM Inserted')
	EXEC ('CREATE TRIGGER tr_' + @TableName + '_Update ON ' + @Owner + '.[' + @TableName + '] FOR UPDATE AS INSERT INTO _shadow_' + @TableName + '(' +  @ListOfFields + 'AuditAction) SELECT ' + @ListOfFields + '''U'' FROM Inserted')
	EXEC ('CREATE TRIGGER tr_' + @TableName + '_Delete ON ' + @Owner + '.[' + @TableName + '] FOR DELETE AS INSERT INTO _shadow_' + @TableName + '(' +  @ListOfFields + 'AuditAction) SELECT ' + @ListOfFields + '''D'' FROM Deleted')

END
GO