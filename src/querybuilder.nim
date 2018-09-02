import strutils
import sequtils

type
  UnaryOperatorType* = enum
    oIsNull,
    oIsNotNull

  ConditionOperator = enum
    oAnd,
    oOr
  
  BinaryOperatorType* = enum
    oEquals,
    oNotEquals,
    oLess,
    oLessEquals,
    oGreater,
    oGreaterEquals,
    oLike,
    oNotLike,
    oIn,
    oNotIn

  JoinType = enum
    jtLeftInner,
    jtLeftOuter,
    jtRightInner,
    jtRightOuter
    
  OrderDirection* = enum
    odAsc,
    odDesc

  IdentifierEscapeMode* = enum
    iemNone,
    iemAnsi,
    iemMySql,
    iemSqlServer

  Node = ref object of RootObj
  
  RawNode = ref object of Node
    sql: string not nil
    params: seq[string] not nil

  TableIdentifier = ref object of Node
    name: string not nil

  ColumnIdentifier = ref object of Node
    table: string # explicit table name is optional
    column: string not nil
    
  Literal = ref object of Node
    value: string

  ListLiteral = ref object of Node
    values: seq[string]
  
  Condition = object
    operator: ConditionOperator
    node: Node not nil
    
  ConditionGroup = seq[Condition]

  UnaryOperator = ref object of Node
    operator: UnaryOperatorType
    operand: Node not nil
    
  BinaryOperator = ref object of Node
    operator: BinaryOperatorType
    left: Node not nil
    right: Node not nil

  NamedExpression = object
    source: Node not nil
    alias: string # the alias is optional
  
  JoinClause = object
    joinType: JoinType
    source: NamedExpression
    conditions: ConditionGroup not nil

  OrderClause = object
    source: Node not nil
    direction: OrderDirection
    
  SelectStatement = ref object of Node
    source: NamedExpression
    fields: seq[NamedExpression] not nil
    joins: seq[JoinClause] not nil
    whereConditionGroup: ConditionGroup not nil
    groups: seq[Node] not nil
    havingConditionGroup: ConditionGroup not nil
    orders: seq[OrderClause] not nil
    offset: int
    limit: int

  StatementBuilder = object
    sql*: string not nil # TODO: make readonly
    params*: seq[string] not nil
    escapeMode: IdentifierEscapeMode
    tablePrefix: string
    
# builder

proc newStatementBuilder(escapeMode: IdentifierEscapeMode = iemNone, tablePrefix: string = nil): auto =
  StatementBuilder(sql: "", params: @[],
                   escapeMode: escapeMode,
                   tablePrefix: tablePrefix)

proc appendSql(output: var StatementBuilder, sql: char) =
  output.sql &= sql

proc appendSql(output: var StatementBuilder, sql: string) =
  output.sql &= sql

proc appendIdentifier(output: var StatementBuilder, name: string) =
  case output.escapeMode:
    of iemAnsi:
      output.appendSql('\'')
      output.appendSql(name)
      output.appendSql('\'')
    of iemMySql:
      output.appendSql('`')
      output.appendSql(name)
      output.appendSql('`')
    of iemSqlServer:
      output.appendSql('[')
      output.appendSql(name)
      output.appendSql(']')
    else:
      output.appendSql(name)

proc appendTableName(output: var StatementBuilder, name: string) =
  if output.tablePrefix == nil:
    output.appendIdentifier(name)
  else:
    output.appendIdentifier(output.tablePrefix & name)

proc appendColumnName(output: var StatementBuilder, column: string) =
  output.appendIdentifier(column)

proc appendColumnName(output: var StatementBuilder, table: string, column: string) =
  if not isNilOrEmpty(table):
    output.appendTableName(table)
    output.appendSql('.')
    
  output.appendColumnName(column)

proc appendValue(output: var StatementBuilder, value: string) =
  output.appendSql('?')
  output.params.add(value)

proc append(output: var StatementBuilder, sql: string, params: varargs[string, `$`]) =
  output.sql &= sql
  output.params.add(params)

proc `$`*(builder: StatementBuilder): string =
  ## Returns a simple SQL representation of this built statement.
  ## Use for debugging purposes only.
  result = ""
  var cursor = 0

  for param in builder.params:
    let found = builder.sql.find('?', cursor)

    if found < 0:
      break
    
    result &= builder.sql.substr[cursor..found - 1]
    result &= '"'
    result &= param
    result &= '"'
      
    cursor = found + 1
    
  result &= builder.sql[cursor..^0]
  
# node
    
method append*(output: var StatementBuilder, exp: Node): void {.base.} =
  return

proc build*(node: Node, escapeMode: IdentifierEscapeMode = iemNone, tablePrefix: string = nil): auto =
  ## Returns an object which holds a SQL representation of the node
  ## that can be used to create a prepared statement.
  result = newStatementBuilder(escapeMode, tablePrefix)  
  result.append(node)
  
proc `$`*(node: Node): string =
  ## Returns a simple SQL representation of the node, for debugging purposes.
  ## To send the query to a database, use build instead.
  $build(node)

template getAllRows*(db: untyped, node: Node): untyped =
  ## Builds the query and returns all the resulting rows.
  let built = node.build()
  db.getAllRows(sql(built.sql), built.params)

template getRow*(db: untyped, node: Node): untyped =
  ## Builds the query and returns the first resulting row.
  let built = node.build()
  db.getRow(sql(built.sql), built.params)

template getValue*(db: untyped, node: Node): untyped =
  ## Builds the query and returns the value of the first row and column.
  let built = node.build()
  db.getValue(sql(built.sql), built.params)

# raw

proc raw*(sql: string, params: varargs[string, `$`]): RawNode =
  ## Allows to inject arbitrary SQL code.
  RawNode(sql: sql, params: toSeq(params.items))

method append(output: var StatementBuilder, exp: RawNode): void =
  output.append(exp.sql, exp.params)

# table

proc table*(name: string): auto = TableIdentifier(name: name)

method append*(output: var StatementBuilder, exp: TableIdentifier): void =
  output.appendTableName(exp.name)
  
# column

proc column*(table: string, column: string): auto = ColumnIdentifier(table: table, column: column)
proc column*(column: string): auto = column(nil, column)

method append*(output: var StatementBuilder, exp: ColumnIdentifier): void =
  output.appendColumnName(exp.table, exp.column)

# literal

proc literal*(value: string): auto = Literal(value: value)

method append*(output: var StatementBuilder, exp: Literal): void =
  output.appendValue(exp.value)

# list literal

proc literal*(values: seq[string]): auto = ListLiteral(values: values)

method append*(output: var StatementBuilder, exp: ListLiteral): void =
  output.appendSql('(')

  for index, value in exp.values:
    if index > 0:
      output.appendSql(", ")

    output.appendValue(value)

  output.appendSql(')')

# aliasable

proc alias(source: Node, alias: string = nil): auto = NamedExpression(source: source, alias: alias)

proc append(output: var StatementBuilder, named: NamedExpression) =
  output.append(named.source)

  if not isNilOrEmpty(named.alias):
    output.appendSql(' ')
    output.appendIdentifier(named.alias)
    
# condition group

proc andCondition(node: Node): auto = Condition(operator: oAnd, node: node)
proc orCondition(node: Node): auto = Condition(operator: oOr, node: node)

proc append(output: var StatementBuilder, conditions: ConditionGroup) =
  for index, condition in conditions:  
    if index > 0:  
      if condition.operator == oOr:
        output.appendSql(" OR ")
      else:
        output.appendSql(" AND ")
    
    output.append(condition.node)
    
# operators

proc cond*(operand: Node, operator: UnaryOperatorType): auto =
  UnaryOperator(operand: operand, operator: operator)

method append(output: var StatementBuilder, exp: UnaryOperator): void =
  output.append(exp.operand)

  if exp.operator == oIsNull:
    output.appendSql(" IS NULL")
  else:
    output.appendSql(" IS NOT NULL")

proc cond*(left: Node, operator: BinaryOperatorType, right: Node): auto =
  BinaryOperator(left: left, operator: operator, right: right)
  
proc cond*(left: Node, right: Node): auto = cond(left, oEquals, right)
  
method append(output: var StatementBuilder, exp: BinaryOperator): void =
  output.append(exp.left)

  case exp.operator:
    of oNotEquals:
      output.appendSql("<>")
    of oLess:
      output.appendSql('<')
    of oLessEquals:
      output.appendSql("<=")
    of oGreater:
      output.appendSql('>')
    of oGreaterEquals:
      output.appendSql(">=")
    of oLike:
      output.appendSql(" LIKE ")
    of oNotLike:
      output.appendSql(" NOT LIKE ")
    of oIn:
      output.appendSql(" IN ")
    of oNotIn:
      output.appendSql(" NOT IN ")
    else:
      output.appendSql('=')

  output.append(exp.right)

# join

proc append(output: var StatementBuilder, join: JoinClause) =
  case join.joinType:
    of jtLeftOuter:
      output.appendSql(" LEFT OUTER JOIN ")
    of jtRightInner:
      output.appendSql(" RIGHT INNER JOIN ")
    of jtRightOuter:
      output.appendSql(" RIGHT OUTER JOIN ")
    else:
      output.appendSql(" JOIN ")

  output.append(join.source)

  if join.conditions.len > 0:
    output.appendSql(" ON (")
    output.append(join.conditions)
    output.appendSql(')')
    
# select

proc newSelect*(source: Node, alias: string = nil): auto =
  ## Creates an object that represents a SELECT statement.
  SelectStatement(source: alias(source, alias),
                  fields: @[],
                  whereConditionGroup: @[],
                  joins: @[],
                  groups: @[],
                  havingConditionGroup: @[],
                  orders: @[],
                  offset: -1, limit: -1)

proc field*(exp: SelectStatement, source: Node, alias: string = nil) =
  ## Adds a column to be selected.
  exp.fields.add(alias(source, alias))
                  
proc join(exp: SelectStatement, joinType: JoinType, source: Node, alias: string, conditions: ConditionGroup) =
  exp.joins.add(JoinClause(joinType: joinType, source: alias(source, alias), conditions: conditions))

proc join*(exp: SelectStatement, source: Node, alias: string, node: Node) =
  ## Adds a LEFT INNER JOIN.
  exp.join(jtLeftInner, source, alias, @[andCondition(node)])

proc outerJoin*(exp: SelectStatement, source: Node, alias: string, node: Node) =
  ## Adds a LEFT OUTER JOIN.
  exp.join(jtLeftOuter, source, alias, @[andCondition(node)])

proc rightJoin*(exp: SelectStatement, source: Node, alias: string, node: Node) =
  ## Adds a RIGHT JOIN.
  exp.join(jtRightInner, source, alias, @[andCondition(node)])

proc rightOuterJoin*(exp: SelectStatement, source: Node, alias: string, node: Node) =
  ## Adds a RIGHT OUTER JOIN.
  exp.join(jtRightOuter, source, alias, @[andCondition(node)])
  
proc where*(exp: SelectStatement, node: Node) =
  ## Adds a WHERE condition, prefixed with the AND operator.
  exp.whereConditionGroup.add(andCondition(node))

proc orWhere*(exp: SelectStatement, node: Node) =
  ## Adds a WHERE condition, prefixed with the OR operator.
  exp.whereConditionGroup.add(orCondition(node))

proc groupBy*(exp: SelectStatement, node: Node) =
  ## Adds a GROUP BY.
  exp.groups.add(node)

proc having*(exp: SelectStatement, node: Node) =
  ## Adds a HAVING condition, prefixed with the AND operator.
  exp.havingConditionGroup.add(andCondition(node))

proc orHaving*(exp: SelectStatement, node: Node) =
  ## Adds a HAVING condition, prefixed with the OR operator.
  exp.havingConditionGroup.add(orCondition(node))
    
proc orderBy*(exp: SelectStatement, node: Node, direction = odAsc) =
  ## Adds a GROUP BY clause.
  exp.orders.add(OrderClause(source: node, direction: direction))
  
proc paginate*(exp: SelectStatement, page: int, pageSize: int) =
  ## Sets the query LIMIT and OFFSET.
  exp.offset = (page - 1) * pageSize
  exp.limit = pageSize
  
method append(output: var StatementBuilder, exp: SelectStatement): void =
  let shouldWrap = output.sql.len > 0

  if shouldWrap: output.appendSql('(')

  output.appendSql("SELECT ")
  
  # fields
  
  if exp.fields.len > 0:
    for index, field in exp.fields:
      if index > 0:
        output.appendSql(", ")

      output.append(field)
  
  else:
    output.appendSql("*")
    
  # from
  
  output.appendSql(" FROM ")
  output.append(exp.source)
  
  # joins
  
  for join in exp.joins:
    output.append(join)
    
  # where
  
  if exp.whereConditionGroup.len > 0:
    output.appendSql(" WHERE ")
    output.append(exp.whereConditionGroup)

  # groups

  if exp.groups.len > 0:
    output.appendSql(" GROUP BY ")

    for index, group in exp.groups:
      if index > 0:
        output.appendSql(", ")

      output.append(group)
    
  # having

  if exp.havingConditionGroup.len > 0:
    output.appendSql(" HAVING ")
    output.append(exp.havingConditionGroup)

  # order

  if exp.orders.len > 0:
    output.appendSql(" ORDER BY ")

    for index, order in exp.orders:
      if index > 0:
        output.appendSql(", ")

      output.append(order.source)

      if order.direction == odDesc: 
        output.appendSql(" DESC")
    
  # pagination
  # numbers are directly embedded in the query because MariaDB rejects them if
  # sent as parameters
   
  if exp.offset >= 0 and exp.limit >= 0:
    output.appendSql(" LIMIT " & $exp.offset & ' ' & $exp.limit)
  
  else:    
    if exp.offset >= 0:
      output.append(" OFFSET " & $exp.offset)
    
    elif exp.limit >= 0:
      output.append(" LIMIT " & $exp.limit)

  if shouldWrap: output.appendSql(')')
