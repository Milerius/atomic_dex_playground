##! Project Import
import ./mm2_api

var balanceChannel*: Channel[BalanceAnswerSuccess]
var myTxHistoryChannel*: Channel[TransactionHistoryAnswerSuccess]

proc initChannels*() =
    balanceChannel.open()
    myTxHistoryChannel.open()