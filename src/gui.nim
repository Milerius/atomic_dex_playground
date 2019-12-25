import os
import asyncdispatch
import strutils
import sequtils
import ui_workflow_nim
import threadpool
import options
import browsers
import times
import json
import std/atomics
import tables

import ./cpp_bindings/boost/multiprecision
import ./balance
import ./coinpaprika_provider
import ./mm2_api
import ./mm2_process
import ./mm2_core
import ./workers_channels
import ./coin_cfg
import ./gui_style
import ./gui_widgets
import ./utils

let
  value_color = ImVec4(x: 128.0 / 255.0, y: 128.0 / 255.0, z: 128.0 / 255.0, w: 1.0)
  loss_color = ImVec4(x: 1, y: 52.0 / 255.0, z: 0, w: 1.0)
  gain_color = ImVec4(x: 80.0 / 255.0, y: 1, z: 118.0 / 255.0, w: 1.0)
  error_color = ImVec4(x: 255.0 / 255.0, y: 20.0 / 255.0, z: 20.0 / 255.0, w: 1);

type SendCoinVars = object
  address_input*: array[100, cchar]
  amount_input*: array[100, cchar]
  withdraw_answer*: WithdrawAnswer
  broadcast_answer*: BroadcastAnswer

var
  is_open = true
  balanceRegistry: Table[string, BalanceAnswerSuccess]
  txHistoryRegistry: Table[string, TransactionHistoryAnswerSuccess]
  providerRegistry: Table[string, string]
  sendCoinRegistry: Table[string, SendCoinVars] = initTable[string, SendCoinVars]()
  allProviderRegistry: Table[string, providerRegistry] = {"EUR": initTable[
      string, string](), "USD": initTable[string, string]()}.toTable()
  curAssetTicker = ""
  curAddress: seq[char]
  curCoin: CoinConfigParams
  curFiat = "USD"
  icons: OrderedTable[string, t_antara_image]
  enableableCoinsSelectList: seq[bool]
  curWindowSize: ImVec2
  enableableCoinsSelectListV: seq[CoinConfigParams]

proc clear(coinVars: var SendCoinVars) =
  coinVars.address_input.reset()
  coinVars.amount_input.reset()

proc mainMenuBar() =
  if igBeginMenuBar():
    if igMenuItem("Open", "Ctrl+A"):
      echo "Open"
    igEndMenuBar()
  else:
    echo "Nop"

proc portfolioEnableCoinView() =
  if igButton("Enable a coin"):
    igOpenPopup("Enable coins")
  var
    popupIsOpen = true
    close = false
  if igBeginPopupModal("Enable coins", addr popupIsOpen, (
      ImGuiWindowFlags.AlwaysAutoResize.int32 or ImGuiWindowFlags.NoMove.int32).ImGuiWindowFlags):
    let coins = getEnableableCoins()
    igText(coins.len == 0 ? "All coins are already enabled!" ! "Select the coins you want to add to your portfolio.")
    if coins.len == 0:
      igSeparator()
    if coins.len > enableableCoinsSelectList.len:
      enableableCoinsSelectList.setLen(coins.len)
      enableableCoinsSelectList.applyIt(false)
    for i, coin in coins:
      if igSelectable(coin["name"].getStr & " (" & coin["coin"].getStr & ")",
          enableableCoinsSelectList[i], ImGuiSelectableFlags.DontClosePopups):
        enableableCoinsSelectList[i] = enableableCoinsSelectList[i] == false
        enableableCoinsSelectListV.add(coin)
    if coins.len == 0 and igButton("Close"):
      close = true
    else:
      if igButton("Enable", ImVec2(x: 120.0, y: 0.0)):
        enableMultipleCoins(enableableCoinsSelectListV)
        close = true
      igSameLine()
      if igButton("Cancel", ImVec2(x: 120.0, y: 0.0)):
        close = true
    if not popupIsOpen or close:
      enableableCoinsSelectList.applyIt(false)
      enableableCoinsSelectListV.setLen(0)
      igCloseCurrentPopup()
    igEndPopup()

proc portfolioGuiCoinNameImg(ticker: string, name: string = "",
    name_first = false) =
  if not icons.hasKey(ticker):
    return
  let
    icon = icons[ticker]
    text = name.len > 0 ? name ! ticker
  if name_first:
    igTextWrapped(text)
    igSameLine()
    igSetCursorPosX(igGetCursorPosX() + 5.0)
  let
    origTextPos = ImVec2(x: igGetCursorPosX(), y: igGetCursorPosY())
    customImgSize = icon.height.float32 * 0.8
  igSetCursorPos(ImVec2(x: origTextPos.x, y: origTextPos.y - (customImgSize -
      igGetFont().fontSize * 1.15) * 0.5))
  igImage(ImTextureID(cast[pointer](cast[ptr cuint](icon.id))), ImVec2(
      x: customImgSize, y: customImgSize))
  if name_first == false:
    var posAfterImg = ImVec2(x: igGetCursorPosX(), y: igGetCursorPosY())
    igSameLine()
    igSetCursorPos(origTextPos)
    igSetCursorPosX(igGetCursorPosX() + customImgSize + 5.0)
    igTextWrapped(text)
    igSetCursorPos(posAfterImg)

proc portfolioCoinsListView() =
  igBeginChild("left pane", ImVec2(x: 180, y: 0), true)
  let coins = getEnabledCoins()
  for i, v in (coins):
    if curAssetTicker.len == 0 or curAddress.len == 0:
      curAssetTicker = v["coin"].getStr
      if balanceRegistry.contains(curAssetTicker):
        curAddress = balanceRegistry[curAssetTicker]["address"].getStr().toSeq()
      curCoin = v
    if igSelectable("##" & v["coin"].getStr, v["coin"].getStr ==
        curAssetTicker):
      curAssetTicker = v["coin"].getStr
      curCoin = v
    igSameLine()
    portfolioGuiCoinNameImg(v["coin"].getStr)
  igEndChild()

proc portfolioTransactionDetailsModal(open_modal: bool, tx: TransactionData) =
  igPushID(tx["tx_hash"].getStr())
  if open_modal:
    igOpenPopup("Transaction Details")
  var is_open = true
  if igBeginPopupModal("Transaction Details", addr is_open, (
      ImGuiWindowFlags.AlwaysAutoResize.int32 or
      ImGuiWindowFlags.NoMove.int32).ImGuiWindowFlags):
    let
      my_balance_change = tx["my_balance_change"].getStr()
      am_i_sender = my_balance_change[0] == '-'
      prefix = am_i_sender ? "" ! "+"
      timestamp = tx["timestamp"].getInt
      human_timestamp = timestamp == 0 ? "" ! $timestamp.fromUnix().format("yyyy-MM-dd hh:mm:ss")
      curFiatRegistry = curFiat == "USD" ? allProviderRegistry["USD"] !
          allProviderRegistry["EUR"]
    igSeparator()
    igText(am_i_sender ? "Sent" ! "Received")
    igTextColored(am_i_sender ? loss_color ! gain_color, prefix &
        my_balance_change & " " & curAssetTicker)
    igSameLine(300)
    igTextColored(value_color, getPriceInFiatFromTx(curFiatRegistry, curCoin,
        TransactionData(tx)) & " " & curFiat)
    if timestamp != 0:
      igSeparator()
      igText("Date")
      igTextColored(value_color, human_timestamp)
    igSeparator()
    igText("To")
    for _, address in tx["to"].getElems:
      igTextColored(value_color, address.getStr)
    igSeparator()
    igText("Fees")
    let fee = FeesDetails(tx["fee_details"])
    var fees = ""
    if fee["amount"].isSome():
      fees = fee["amount"].get().getStr()
    elif fee["total_fee"].isSome():
      fees = fee["total_fee"].get().getStr()
    igTextColored(value_color, fees)
    igSeparator()
    igText("Transaction hash")
    igTextColored(value_color, tx["tx_hash"].getStr())
    igSeparator()
    igText("Block Height")
    igTextColored(value_color, $tx["block_height"].getInt())
    igSeparator()
    igText("Confirmations")
    igTextColored(value_color, $tx["confirmations"].get().getInt())
    igSeparator()
    if igButton("Close"):
      igCloseCurrentPopup()
    igSameLine()
    if igButton("View in Explorer"):
      openDefaultBrowser(curCoin["explorer_url"].getElems()[0].getStr() &
          "tx/" & tx["tx_hash"].getStr())
    igEndPopup()
  igPopID()
  return

proc portfolioTransactionView() =
  if txHistoryRegistry.contains(curAssetTicker):
    let transactions = txHistoryRegistry[curAssetTicker]
    let tx_len = transactions["result"]["transactions"].getElems.len
    if tx_len > 0:
      for i, curTx in transactions["result"]["transactions"].getElems:
        let
          timestamp = curTx["timestamp"].getInt
          human_timestamp = timestamp == 0 ? "" ! $timestamp.fromUnix().format("yyyy-MM-dd hh:mm:ss")
          my_balance_change = curTx["my_balance_change"].getStr()
          am_i_sender = my_balance_change[0] == '-'
          prefix = am_i_sender ? "" ! "+"
          tx_color = am_i_sender ? loss_color ! gain_color
          address = am_i_sender ? curTx["to"].getElems()[0].getStr() ! curTx[
              "from"].getElems()[0].getStr()
          curFiatRegistry = curFiat == "USD" ? allProviderRegistry["USD"] !
              allProviderRegistry["EUR"]
        var open_modal = false
        igBeginGroup()
        igText(human_timestamp)
        igSameLine(300.0)
        igTextColored(tx_color, prefix & my_balance_change & " " & curAssetTicker)
        igTextColored(value_color, address)
        igSameLine(300.0)
        igTextColored(value_color, getPriceInFiatFromTx(curFiatRegistry,
            curCoin, TransactionData(curTx)) & " " & curFiat)
        igEndGroup()
        if igIsItemClicked():
          open_modal = true
        portfolioTransactionDetailsModal(open_modal, TransactionData(curTx))
        if i != tx_len:
          igSeparator()
    else:
      igText("No transactions")

proc portfolioReceiveView() =
  if curAddress.len > 0:
    igText("Share the address below to receive coins")
    igPushItemWidth(100.0 * igGetFontSize() * 0.5)
    igInputText("##receive_address", addr curAddress[0], curAddress.len().uint,
        (ImGuiInputTextFlags.ReadOnly.int32 or
    ImGuiInputTextFlags.AutoSelectAll.int32).ImGuiInputTextFlags)
    igPopItemWidth()

proc input_filter_coin_address(data: ptr ImGuiInputTextCallbackData): int32 {.cdecl.} =
  if data.userData == nil:
    return 1
  var str = cast[cstring](data.userData)
  var c = data.eventChar.char
  var valid = str.len() < 40 and isAlphaNumeric(c)
  result = valid ? 0'i32 ! 1'i32

proc input_filter_coin_amount(data: ptr ImGuiInputTextCallbackData): int32 {.cdecl.} =
  if data.userData == nil:
    return 1
  var str: string = $cast[cstring](data.userData)
  var c = data.eventChar.char
  var n = str.count('.')
  if n == 1 and c == '.':
    return 1
  result = isDigit(c) or c == '.' ? 0'i32 ! 1'i32

proc portfolioSendView() =
  if curAssetTicker.len == 0:
    return
  var send_vars = sendCoinRegistry.mgetOrPut(curAssetTicker, SendCoinVars())
  var
    withdraw_answer = send_vars.withdraw_answer
    broadcast_answer = send_vars.broadcast_answer
    amount: string
    address: string
  let has_error = withdraw_answer.error.isSome()
  if broadcast_answer.success.isSome() or broadcast_answer.error.isSome():
    if broadcast_answer.error.isSome():
      echo "Transaction Failed"
    else:
      echo "Transaction Success"
  elif has_error or not withdraw_answer.success.isSome():
    let width = 35 * igGetFontSize() * 0.5
    igSetNextItemWidth(width)
    igInputText("Address##send_coin_address_input", send_vars.address_input.addr, 
      send_vars.address_input.len().uint, ImGuiInputTextFlags.CallbackCharFilter, input_filter_coin_address, send_vars.address_input.addr)
    igSetNextItemWidth(width)
    igInputText("Amount##send_coin_amount_input", send_vars.amount_input.addr, 
      send_vars.amount_input.len().uint, ImGuiInputTextFlags.CallbackCharFilter, input_filter_coin_amount, send_vars.amount_input.addr)
    igSameLine()
    var 
      balance = balanceRegistry[curAssetTicker].myBalance()
      balance_f = balanceRegistry[curAssetTicker].myBalanceF()
    amount = $cast[cstring](send_vars.amount_input.addr)
    address = $cast[cstring](send_vars.address_input.addr)
    if igButton("MAX##send_coin_max_amount_button") or not balanceRegistry[curAssetTicker].doIHaveEnoughFunds(amount):
      for i, v in balance:
        send_vars.amount_input[i] = balance[i]
    if igButton("Send##send_coin_button"):
      var req = create(WithdrawRequestParams, curAssetTicker, address, amount, amount == balance)
      return
    if has_error:
      igTextColored(error_color, "error")
    sendCoinRegistry[curAssetTicker] = send_vars # we save
  else:
    return
    

proc portfolioCoinDetails() =
  igBeginChild("item view", ImVec2(x: 0, y: 0), true)
  portfolioGuiCoinNameImg(curAssetTicker)
  igSeparator()
  if balanceRegistry.contains(curAssetTicker):
    if allProviderRegistry[curFiat].contains(curAssetTicker):
      let price = allProviderRegistry[curFiat][curAssetTicker]
      igText("\uf24e" & " Balance: " & balanceRegistry[
          curAssetTicker].myBalance() & " " & curAssetTicker & " (" & 
          getPriceInFiat(price, balanceRegistry, curAssetTicker) &
          " " & curFiat & ")")
    else:
      igText("\uf24e" & " Balance: " & balanceRegistry[curAssetTicker].myBalance() & " " & curAssetTicker & 
          " (" & "0.00 " & curFiat & ")")
  igSeparator()
  if igBeginTabBar("##Tabs", ImGuiTabBarFlags.None):
    if igBeginTabItem("Transactions"):
      portfolioTransactionView()
      igEndTabItem()
    if igBeginTabItem("Receive"):
      portfolioReceiveView()
      igEndTabItem()
    if igBeginTabItem("Send"):
      portfolioSendView()
      igEndTabItem()
    igEndTabBar()
  igEndChild()

proc portfolioView() =
  igText("Total Balance:" & " " & getWholeBalanceFiat(allProviderRegistry[
      curFiat], balanceRegistry) & " " & curFiat)
  portfolioEnableCoinView()
  portfolioCoinsListView()
  igSameLine()
  portfolioCoinDetails()

proc mainView() =
  mainMenuBar()
  if igBeginTabBar("##Tabs", ImGuiTabBarFlags.None):
    if (igBeginTabItem("Portfolio")):
      portfolioView()
      igEndTabItem()
    igEndTabBar()

proc waitingView() =
  igText("Loading, please wait...")
  let
    radius = 30.0
    pos = ImVec2(x: igGetWindowWidth() * 0.5f - radius, y: igGetWindowHeight() *
        0.5f - radius)
  igSetCursorPos(pos)
  when not defined(windows):
    loadingIndicatorCircle("foo", radius, bright_color, dark_color, 9, 1.5)

proc retrieveChannelsData() =
  let balance_res = balanceChannel.tryRecv()
  if balance_res.dataAvailable:
    var r = balance_res.msg.JsonNode
    balanceRegistry[r["coin"].getStr] = balance_res.msg
  let tx_res = myTxHistoryChannel.tryRecv()
  if tx_res.dataAvailable:
    var r = tx_res.msg.JsonNode
    txHistoryRegistry[r["coin"].getStr] = tx_res.msg
  let provider_res = paprikaChannel.tryRecv()
  if provider_res.dataAvailable:
    let tunnel = provider_res.msg
    for i, cur in tunnel:
      allProviderRegistry[cur.fiat][cur.ticker] = cur.price

proc update*(ctx: ptr t_antara_ui) =
  retrieveChannelsData()
  igSetNextWindowSize(ImVec2(x: 1280, y: 720), ImGuiCond.FirstUseEver)
  igBegin("atomicDex", addr is_open, (ImGuiWindowFlags.NoCollapse.int32 or
      ImGuiWindowFlags.MenuBar.int32).ImGuiWindowFlags)
  curWindowSize = igGetWindowSize()
  if not is_open:
    antara_close_window(ctx)
  if mm2IsRunning.load() == false:
    waitingView()
  else:
    mainView()
  igEnd()

proc loadImg(ctx: ptr t_antara_ui, id: string, path: string) {.async.} =
  icons[id] = antara_load_image_ws(ctx, path)

proc init*(ctx: ptr t_antara_ui) =
  var textures_path = getAssetsPath() & "/textures"
  for kind, path in walkDir(textures_path):
    var id = path.extractFilename.changeFileExt("").toUpperAscii
    asyncCheck loadImg(ctx, id, path)
  setKomodoStyle(ctx)
