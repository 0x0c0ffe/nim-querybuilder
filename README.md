# SQL query builder for Nim

This package facilitates building SQL queries that might conditionally need to
be changed at runtime.

This is a work in progress, and only SELECT statements are implemented.

Tested with Nim 0.18 and MariaDB 10.3.

## Examples

Build a query and send it to a MySQL server as a prepared statement:

```nim
import src/querybuilder
import db_mysql

# select from the post table ("p" is the alias)
let query = newSelect(table "post", "p")

# join each author (ON u.id=p.author_id)
query.join(table "user", "u", cond(column("u", "id"), column("p", "author_id")))

# load the post title and autor name (SELECT p.title, u.username)
query.field(column("p", "title"))
query.field(column("u", "username"))

# only show published posts (WHERE published=1)
query.where(cond(column("p", "published"), literal "1"))

# and where its author role is either admin or publisher
query.where(cond(column("u", "role"), oIn, literal(@["admin", "publisher"])))

# connect to the database and display each row

let db = open("localhost", "user", "password", "dbname")

for it in db.getAllRows(query):
  echo it

db.close()
```

To debug the generated SQL:

```nim
echo query
```

Displays:

```sql
SELECT p.title, u.username FROM post p JOIN user u ON (u.id=p.author_id) WHERE p.published="1" AND u.role IN ("admin", "publisher")
```

Note that printing the query this way does not properly escape bound parameters,
and is only meant for debugging purposes.
