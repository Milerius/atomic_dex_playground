import logging

##! Project Import
import ./mm2_api

type CoinpaprikaPrice* = tuple
    ticker: string
    price: string
    fiat: string

var paprikaChannel*: Channel[array[2, CoinpaprikaPrice]]
var balanceChannel*: Channel[BalanceAnswerSuccess]
var myTxHistoryChannel*: Channel[TransactionHistoryAnswerSuccess]

proc initChannels*() =
    balanceChannel.open()
    log(lvlInfo, "balance channel open")
    myTxHistoryChannel.open()
    log(lvlInfo, "tx history channel open")
    paprikaChannel.open()
    info("paprika channel open")