mysqlsh ${1}:3306 --schema=APMCFG --sql -u root --password="P@ssw0rd" -e 'update USER_PROFILE set password = "$2a$10$97A.Zlo0AQgyYS7M7HxdoOISHEEWuQ9Jv71RQJjEE9M4W1N8QfPSW" where username = "admin"'