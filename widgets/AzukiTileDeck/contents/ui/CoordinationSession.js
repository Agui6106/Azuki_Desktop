.pragma library

var _clientId = ""

function clientId() {
    if (_clientId === "") {
        _clientId = Date.now().toString(36) + "-"
                  + Math.floor(Math.random() * 0x100000000).toString(36)
                  + "-" + Math.floor(Math.random() * 0x100000000).toString(36)
    }
    return _clientId
}
