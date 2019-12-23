import options
import json

import ./mm2_api
import ./workers_channels

proc processTxHistory*(ticker: string, limit: int = 50) : bool =
    {.gcsafe.}:
        var req = create(TransactionHistoryRequestParams, ticker, limit, none(string))
        var answer = rpcMyTxHistory(req)
        if answer.error.isSome:
            echo answer.error.get()["error"].getStr
            result = false
        else:
            discard myTxHistoryChannel.trySend(answer.success.get())
            result = true