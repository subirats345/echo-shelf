function parseKeyValue(raw) {
  var result = {}
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var separator = lines[i].indexOf("\t")
    if (separator <= 0) continue
    result[lines[i].substring(0, separator)] = lines[i].substring(separator + 1).trim()
  }

  return result
}
