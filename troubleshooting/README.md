# Troubleshooting Workshop - Student labs

This workshop walks through the process of troubleshooting a problematic cluster.

## Table Of Contents

- [Demo multiregion deployment](multiregion/README.md)

- [Demo singleregion deployment](singleregion-hotrange-gcp/README.md)

## Labs Prerequisites

1. A modern web browser
2. A SSH client:
    - Terminal (MacOS/Linux)
    - Powershell or Putty (Windows)

## Lab 0 - Create database and load data

SSH into the jumpbox using the IP address and SSH key provided by the instructor, for example:

```bash
ssh -i ~/workshop.pem ubuntu@12.34.56.78
```

Once logged in the jumpbox, connect to the database

```bash
cockroach sql --insecure
```

At the SQL prompt, create your database

```sql
CREATE DATABASE <your-name>;
USE <your-name>;
```

You can now import the data

```sql
CREATE TABLE a (
    id UUID NOT NULL,
    alpha STRING NOT NULL,
    bravo BOOL NOT NULL,
    charlie STRING NULL,
    delta BOOL NOT NULL,
    echo UUID NULL,
    foxtrot STRING NOT NULL,
    CONSTRAINT "primary" PRIMARY KEY (id ASC),
    INDEX a_foxtrot_delta_bravo_idx (foxtrot ASC, delta ASC, bravo ASC),
    INDEX a_echo_idx (echo ASC),
    FAMILY "primary" (id, alpha, bravo, charlie, delta, echo, foxtrot)
); 

IMPORT INTO a 
CSV DATA (
    'https://github.com/cockroachlabs/workshop_labs/raw/master/troubleshooting/data/a.csv.gz'
) WITH skip = '1';

CREATE TABLE m (
    echo UUID NOT NULL,
    id UUID NOT NULL,
    CONSTRAINT "primary" PRIMARY KEY (echo ASC, id ASC),
    INDEX m_id_echo_idx (id ASC, echo ASC),
    FAMILY "primary" (echo, id)
);

IMPORT INTO m
CSV DATA (
    'https://github.com/cockroachlabs/workshop_labs/raw/master/troubleshooting/data/m.csv.gz'
) WITH skip = '1';

CREATE TABLE u (
    id UUID NOT NULL,
    golf STRING NOT NULL,
    CONSTRAINT "primary" PRIMARY KEY (id ASC),
    INDEX u_golf_idx (golf ASC, id ASC),
    FAMILY "primary" (id, golf)
);

IMPORT INTO u
CSV DATA (
    'https://github.com/cockroachlabs/workshop_labs/raw/master/troubleshooting/data/u.csv.gz'
) WITH skip = '1';

-- generate table statistics for the cost-based optimizer to use
CREATE STATISTICS statu FROM u;
CREATE STATISTICS stata FROM a;
CREATE STATISTICS statm FROM m;
```

Perfect, good job, we've replicated the schema locally with some dummy data.

## Lab 1 - Optimization

Below is the query the customer is running. Examine the query plan

```sql
-- very slow query
EXPLAIN (VERBOSE) SELECT a.id, a.charlie
FROM a
WHERE a.foxtrot = '106718'
  AND a.delta = true
  AND a.bravo = false
  AND a.echo
    IN (SELECT echo 
        FROM m
        WHERE id = (SELECT id FROM u WHERE golf = 'N722855')
        );
```

```text
                                               info
--------------------------------------------------------------------------------------------------
  distribution: full
  vectorized: true

  • root
  │ columns: (id, charlie)
  │
  ├── • project
  │   │ columns: (id, charlie)
  │   │ estimated row count: 1
  │   │
  │   └── • lookup join (semi)
  │       │ columns: (id, bravo, charlie, delta, echo, foxtrot)
  │       │ estimated row count: 1
  │       │ table: m@primary
  │       │ equality: (echo) = (echo)
  │       │ pred: id = @S1
  │       │
  │       └── • index join
  │           │ columns: (id, bravo, charlie, delta, echo, foxtrot)
  │           │ estimated row count: 1
  │           │ table: a@primary
  │           │ key columns: id
  │           │
  │           └── • scan
  │                 columns: (id, bravo, delta, foxtrot)
  │                 estimated row count: 1 (0.02% of the table; stats collected 1 minute ago)
  │                 table: a@a_foxtrot_delta_bravo_idx
  │                 spans: /"106718"/1/0-/"106718"/1/1
  │
  └── • subquery
      │ id: @S1
      │ original sql: (SELECT id FROM u WHERE golf = 'N722855')
      │ exec mode: one row
      │
      └── • max1row
          │ columns: (id)
          │ estimated row count: 1
          │
          └── • project
              │ columns: (id)
              │ estimated row count: 1
              │
              └── • scan
                    columns: (id, golf)
                    estimated row count: 1 (<0.01% of the table; stats collected 23 seconds ago)
                    table: u@u_golf_idx
                    spans: /"N722855"-/"N722855"/PrefixEnd
(47 rows)
```

Ok, that's a bit complex, there are 3 nested queries. Let's break it down one by one

### Index Join

Let's pull the plan again, hardcoding the values returned by the two subqueries. We know that the return value is an array of UUIDs.

```sql
EXPLAIN (VERBOSE) SELECT a.id, a.charlie
FROM a
WHERE a.foxtrot = '106718'
  AND a.delta = true
  AND a.bravo = false
  AND a.echo
    IN ('e3e70682-c209-4cac-a29f-6fbed82c07cd', 'e3e70682-c209-4cac-a29f-6fbed82c07ce', '13e70682-c209-4cac-a29f-6fbed82c07cd');
```

```text
                                                                       info
--------------------------------------------------------------------------------------------------------------------------------------------------
  distribution: local
  vectorized: true

  • project
  │ columns: (id, charlie)
  │ estimated row count: 1
  │
  └── • filter
      │ columns: (id, bravo, charlie, delta, echo, foxtrot)
      │ estimated row count: 1
      │ filter: echo IN ('13e70682-c209-4cac-a29f-6fbed82c07cd', 'e3e70682-c209-4cac-a29f-6fbed82c07cd', 'e3e70682-c209-4cac-a29f-6fbed82c07ce')
      │
      └── • index join
          │ columns: (id, bravo, charlie, delta, echo, foxtrot)
          │ estimated row count: 1
          │ table: a@primary
          │ key columns: id
          │
          └── • scan
                columns: (id, bravo, delta, foxtrot)
                estimated row count: 1 (0.02% of the table; stats collected 2 minutes ago)
                table: a@a_foxtrot_delta_bravo_idx
                spans: /"106718"/1/0-/"106718"/1/1
(23 rows)
```

We have an index join, which is used to fetch from index/table `a@primary` the fields missing from the index `a@a_foxtrot_delta_bravo_idx`, used to filter for field `echo`.

This is easely fixable: let's recreate index `a@a_foxtrot_delta_bravo_idx` to include the missing field, `charlie`.

```sql
-- recreate the index
DROP INDEX a_foxtrot_delta_bravo_idx;
-- we don't really need to explicitly add 'id', as it is added implicitly
CREATE INDEX a_foxtrot_delta_bravo_echo_idx on a(foxtrot ASC, delta ASC, bravo ASC, echo ASC) storing (charlie);

-- confirm id have been added, just so you know
SHOW INDEXES FROM a;
```

```text
  table_name |           index_name           | non_unique | seq_in_index | column_name | direction | storing | implicit
-------------+--------------------------------+------------+--------------+-------------+-----------+---------+-----------
  a          | a_echo_idx                     |    true    |            1 | echo        | ASC       |  false  |  false
  a          | a_echo_idx                     |    true    |            2 | id          | ASC       |  false  |   true
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            1 | foxtrot     | ASC       |  false  |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            2 | delta       | ASC       |  false  |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            3 | bravo       | ASC       |  false  |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            4 | echo        | ASC       |  false  |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            5 | charlie     | N/A       |  true   |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            6 | id          | ASC       |  false  |   true
  a          | primary                        |   false    |            1 | id          | ASC       |  false  |  false
(9 rows)
```

Pull the query plan again, and you should see that an index-join is no longer required

```sql
EXPLAIN (VERBOSE) SELECT a.id, a.charlie
FROM a
WHERE a.foxtrot = '106718'
  AND a.delta = true
  AND a.bravo = false
  AND a.echo
    IN ('e3e70682-c209-4cac-a29f-6fbed82c07cd', 'e3e70682-c209-4cac-a29f-6fbed82c07ce', '13e70682-c209-4cac-a29f-6fbed82c07cd');
```

```text
   info
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  distribution: local
  vectorized: true

  • project
  │ columns: (id, charlie)
  │ estimated row count: 1
  │
  └── • scan
        columns: (id, bravo, charlie, delta, echo, foxtrot)
        estimated row count: 1 (0.02% of the table; stats collected 15 seconds ago)
        table: a@a_foxtrot_delta_bravo_echo_idx
        spans: /"106718"/1/0/"\x13\xe7\x06\x82\xc2\tL\xac\xa2\x9fo\xbe\xd8,\a\xcd"-/"106718"/1/0/"\x13\xe7\x06\x82\xc2\tL\xac\xa2\x9fo\xbe\xd8,\a\xcd"/PrefixEnd /"106718"/1/0/"\xe3\xe7\x06\x82\xc2\tL\xac\xa2\x9fo\xbe\xd8,\a\xcd"-/"106718"/1/0/"\xe3\xe7\x06\x82\xc2\tL\xac\xa2\x9fo\xbe\xd8,\a\xce"/PrefixEnd
(12 rows)
```

Good, that was easy! Always look out for index-joins, and for ways to rearrange the order of the fields that compose your key to be as efficient as possible:
in this case, the most uncommon field is `foxtrot`, so we put it at the beginning of our index key so the opt can filter out as many rows, and as quickly, as possible.

### Subquery

Let's pull the plan for the child subquery, the innermost of the two.

```sql
EXPLAIN (VERBOSE) SELECT id FROM u WHERE golf = 'N722855';
```

```text
                                        info
-------------------------------------------------------------------------------------
  distribution: local
  vectorized: true

  • project
  │ columns: (id)
  │ estimated row count: 1
  │
  └── • scan
        columns: (id, golf)
        estimated row count: 1 (<0.01% of the table; stats collected 3 minutes ago)
        table: u@u_golf_idx
        spans: /"N722855"-/"N722855"/PrefixEnd
(12 rows)
```

Perfect, we see that the optimizer is correctly using the index.

Let's pull the plan for its parent

```sql
EXPLAIN (VERBOSE) SELECT echo
FROM m
WHERE id = (
  SELECT id FROM u WHERE golf = 'N722855');
```

```text
                                              info
-------------------------------------------------------------------------------------------------
  distribution: full
  vectorized: true

  • root
  │ columns: (echo)
  │
  ├── • project
  │   │ columns: (echo)
  │   │ estimated row count: 333,333
  │   │
  │   └── • filter
  │       │ columns: (echo, id)
  │       │ estimated row count: 333,333
  │       │ filter: id = @S1
  │       │
  │       └── • scan
  │             columns: (echo, id)
  │             estimated row count: 999,999 (100% of the table; stats collected 4 minutes ago)
  │             table: m@primary
  │             spans: FULL SCAN
  │
  └── • subquery
      │ id: @S1
      │ original sql: (SELECT id FROM u WHERE golf = 'N722855')
      │ exec mode: one row
      │
      └── • max1row
          │ columns: (id)
          │ estimated row count: 1
          │
          └── • project
              │ columns: (id)
              │ estimated row count: 1
              │
              └── • scan
                    columns: (id, golf)
                    estimated row count: 1 (<0.01% of the table; stats collected 3 minutes ago)
                    table: u@u_golf_idx
                    spans: /"N722855"-/"N722855"/PrefixEnd
(39 rows)
```

Full scan, why? The child subquery returns 1 value, and we have indexes on both fields of table `m`. So why is it doing a full scan?

Confirm the indexes are actually accounted by the optimizer by replacing the subquery with an actual value

```sql
-- using a random UUID instead of subquery
EXPLAIN (VERBOSE) SELECT echo
FROM m
WHERE id = 'e3e70682-c209-4cac-a29f-6fbed82c07cd';
```

```text
    tree    |        field        |                                                       description                                                       |  columns   | ordering
------------+---------------------+-------------------------------------------------------------------------------------------------------------------------+------------+-----------
            | distribution        | local                                                                                                                   |            |
            | vectorized          | false                                                                                                                   |            |
  project   |                     |                                                                                                                         | (echo)     |
   │        | estimated row count | 1                                                                                                                       |            |
   └── scan |                     |                                                                                                                         | (echo, id) |
            | estimated row count | 1                                                                                                                       |            |
            | table               | m@m_id_echo_idx                                                                                                         |            |
            | spans               | /"\xe3\xe7\x06\x82\xc2\tL\xac\xa2\x9fo\xbe\xd8,\a\xcd"-/"\xe3\xe7\x06\x82\xc2\tL\xac\xa2\x9fo\xbe\xd8,\a\xcd"/PrefixEnd |            |
```

Ok, the Opt is using the index as expected, but it doesn't with the subquery.
You raise this issue with CockroachDB Support, and they confirm you run into a known issue, [7042](https://github.com/cockroachdb/cockroach/issues/7042).

The workaround to fix this, is to rewrite your query to avoid subqueries.

You rewrite your queries, and came up with below proposed implementations

### Using IN()

```sql
EXPLAIN (VERBOSE) SELECT a.id, a.charlie
FROM a
WHERE a.foxtrot = 'y4xbSD8ufOGYW3I'
  AND a.delta = true
  AND a.bravo = false
  AND a.echo
    IN (SELECT m.echo FROM m INNER JOIN u ON m.id = u.id AND u.golf = 'ABCDEF');
```

```text
                                            info
---------------------------------------------------------------------------------------------
  distribution: full
  vectorized: true

  • project
  │ columns: (id, charlie)
  │ estimated row count: 1
  │
  └── • hash join (right semi)
      │ columns: (id, bravo, charlie, delta, echo, foxtrot)
      │ estimated row count: 1
      │ equality: (echo) = (echo)
      │
      ├── • lookup join (inner)
      │   │ columns: (id, golf, echo, id)
      │   │ estimated row count: 1
      │   │ table: m@m_id_echo_idx
      │   │ equality: (id) = (id)
      │   │
      │   └── • scan
      │         columns: (id, golf)
      │         estimated row count: 1 (<0.01% of the table; stats collected 8 minutes ago)
      │         table: u@u_golf_idx
      │         spans: /"ABCDEF"-/"ABCDEF"/PrefixEnd
      │
      └── • scan
            columns: (id, bravo, charlie, delta, echo, foxtrot)
            estimated row count: 1 (0.02% of the table; stats collected 6 minutes ago)
            table: a@a_foxtrot_delta_bravo_echo_idx
            spans: /"y4xbSD8ufOGYW3I"/1/0-/"y4xbSD8ufOGYW3I"/1/1
(29 rows)
```

### Using 3 joins

```sql
EXPLAIN (VERBOSE) SELECT a.id, a.charlie
FROM a INNER JOIN m ON a.echo = m.echo INNER JOIN u ON m.id = u.id
WHERE a.foxtrot = 'y4xbSD8ufOGYW3I'
  AND a.delta = true
  AND a.bravo = false
  and u.golf = 'ABCDEF';
```

```text
                                                       info
------------------------------------------------------------------------------------------------------------------
  distribution: full
  vectorized: true

  • project
  │ columns: (id, charlie)
  │ estimated row count: 1
  │
  └── • project
      │ columns: (id, bravo, charlie, delta, echo, foxtrot, echo, id, id, golf)
      │ estimated row count: 1
      │
      └── • lookup join (inner)
          │ columns: ("lookup_join_const_col_@15", id, bravo, charlie, delta, echo, foxtrot, echo, id, id, golf)
          │ table: u@u_golf_idx
          │ equality: (lookup_join_const_col_@15, id) = (golf,id)
          │ equality cols are key
          │
          └── • render
              │ columns: ("lookup_join_const_col_@15", id, bravo, charlie, delta, echo, foxtrot, echo, id)
              │ estimated row count: 1
              │ render lookup_join_const_col_@15: 'ABCDEF'
              │ render id: id
              │ render bravo: bravo
              │ render charlie: charlie
              │ render delta: delta
              │ render echo: echo
              │ render foxtrot: foxtrot
              │ render echo: echo
              │ render id: id
              │
              └── • lookup join (inner)
                  │ columns: (id, bravo, charlie, delta, echo, foxtrot, echo, id)
                  │ estimated row count: 1
                  │ table: m@primary
                  │ equality: (echo) = (echo)
                  │
                  └── • scan
                        columns: (id, bravo, charlie, delta, echo, foxtrot)
                        estimated row count: 1 (0.02% of the table; stats collected 3 minutes ago)
                        table: a@a_foxtrot_delta_bravo_echo_idx
                        spans: /"y4xbSD8ufOGYW3I"/1/0-/"y4xbSD8ufOGYW3I"/1/1
```

Congratulations, you reached the end of this exercise! What's left to be done, is testing these above 2 solutions in the real cluster and see how they perform.
Then, you can always iterate over the troubleshooting exercise to further fine tune your query.

## Reference

We use [carota](https://pypi.org/project/carota/) to generate the random datasets.

```bash
# create the dummy data
carota -r 5000 -t "uuid; string::size=15; choices::list=true false; string::size=15; choices::list=true false; uuid; string::size=15" -o a.csv
carota -r 1000000 -t "uuid; uuid" -o m.csv
carota -r 300000 -t "uuid; string::size=7" -o u.csv
```
