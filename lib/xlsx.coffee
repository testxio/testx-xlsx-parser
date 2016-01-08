q = require 'q'
xlsx = require 'xlsx'

formulas = require './formulas'

exports.parse = (xlsFile, sheet) ->
  deferred = q.defer()
  wb = xlsx.readFile xlsFile,
    cellNF: true
    cellDates: true
  calcWb wb.Sheets
  if scriptSheet = wb.Sheets[sheet]
    rows = getRows scriptSheet
    steps = for row, i in rows
      getKeyword(rows, i)
    deferred.resolve
      steps: (s for s in steps when s)
  else
    deferred.reject(new Error("There is no sheet '#{sheet}' in file '#{xlsFile}'!"))
  deferred.promise

calcWb = (sheets) ->
  formulaUtils = require './utils'

  toMatrix = (targetSheet, ref1, ref2) ->
    charRange = (a,b) -> [a.charCodeAt(0)..b.charCodeAt(0)].map (c) -> String.fromCharCode c
    [startCol,startRow] = (ref1.match /([A-Z]+)([0-9]+)/)[1..2]
    [endCol, endRow] = (ref2.match /([A-Z]+)([0-9]+)/)[1..2]

    for row in [(parseInt startRow)..(parseInt endRow)]
      for col in charRange(startCol, endCol)
        resolveRef targetSheet, "#{col}#{row}"

  resolveRef = (sheetName, ref) ->
    [targetSheet, targetRef] = [sheetName, ref]
    if crossSheetRef = ref.match /^'?([^\[\]\*\?\:\/\\']+)'?!([A-Z]+[0-9]+)/
      [targetSheet, targetRef] = crossSheetRef[1..2]
    if rangeRef = ref.match /\$?([A-Z]+)\$?([0-9]+):\$?([A-Z]+)\$?([0-9]+)/
      return toMatrix targetSheet, "#{rangeRef[1]}#{rangeRef[2]}", "#{rangeRef[3]}#{rangeRef[4]}"
    cell = sheets[targetSheet]?[targetRef]
    if cell?.f and not cell?.calculated
      cell.v = cell.calculated = calc targetSheet, targetRef
    else
      cell?.v or ''

  calc = (sheetName, ref) ->
    cell = sheets[sheetName]?[ref]
    frm = cell.f.replace(/&/g, '+').replace(/\n/g, ' ').replace(/\r/g, '')
    eval formulaUtils.format(frm, sheetName)

  calcSheet = (name, sheet) ->
    for cellRef, cellVal of sheet
      if cellVal.f
        resolveRef name, cellRef
      else
        cellVal.v = cellVal.w

  for shName, sh of sheets
    calcSheet shName, sh

getRows = (sheet) ->
  r = /([a-zA-Z]+)(\d+)/i
  rows = []
  for key, value of sheet
    if key[0] != '!'
      [match, col, row] = r.exec key
      row = parseInt row
      col = col.toUpperCase()
      unless rows[row] then rows[row] = []
      rows[row][col] = value
  rows

getKeyword = (rows, i) ->
  row = rows[i]
  prevRow = rows[i - 1]
  if row?['A']?.v
    [match, name, ignore, comment] = /([^\[|\]]*)(\[(.*)\])?/.exec row['A'].v
    keyword =
      name: name.trim()
      meta:
        Row: i
        "Full name": row['A'].v
        Comment: comment?.trim() || ''
      arguments: {}
    if rows[i - 1] # are there any arguments at all?
      cols = Object.keys(rows[i - 1]).sort (l, r) -> l > r
      for col in cols
        keyword.arguments[prevRow[col]?.v] = xlsx.SSF.format(row[col]?.z, row[col]?.v) || ''
    keyword
  else
    null
