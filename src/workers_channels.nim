import ./mm2_api

var balanceChannel*: Channel[BalanceAnswerSuccess]

proc initChannels*() =
    balanceChannel.open()