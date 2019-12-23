import logging

##! Project Import
import ./mm2_api

var balanceChannel*: Channel[BalanceAnswerSuccess]
var myTxHistoryChannel*: Channel[TransactionHistoryAnswerSuccess]

proc initChannels*() =
    balanceChannel.open()
    log(lvlInfo, "balance channel open")
    myTxHistoryChannel.open()
    log(lvlInfo, "tx history channel open")