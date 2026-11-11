.pragma library

// Keep date headings, but let ListView instantiate individual rows instead of entire days.
function flatten(groups) {
  var rows = []
  groups.forEach(function(group) {
    group.items.forEach(function(item, index) {
      var row = Object.assign({}, item)
      if (index === 0) { row._groupLabel = group.label; row._groupCount = group.items.length }
      rows.push(row)
    })
  })
  return rows
}
