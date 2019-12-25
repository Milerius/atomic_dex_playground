import httpclient
import json
import options
import sequtils
import logging
import tables

import jsonschema

import ./coin_cfg

## Local global module variable
let lgEndpoint = "http://127.0.0.1:7783"

proc processPost(data: JsonNode) : string =
    debug("req ", $data)
    var client = newHttpClient()
    result = client.postContent(lgEndpoint, body = $data)
    debug("resp", result)

jsonSchema:
    ElectrumRequestParams:
        coin: string
        servers: ElectrumServerParams[]
        tx_history : bool
    ElectrumAnswerSuccess:
        address: string
        balance: string
        "result": string
    ElectrumAnswerError:
        error: string
    BalanceRequestParams:
        coin: string
    BalanceAnswerSuccess:
        address: string
        balance: string
        locked_by_swaps: string
        coin: string
    BalanceAnswerError:
        error: string
    TransactionHistoryRequestParams:
        coin: string
        limit: int
        from_id ?: string
    StatusAdditionalInfo:
        transactions_left ?: int
        code ?: int
        message ?: string
        blocks_left ?: int
    StatusData:
        state: string
        additional_info ?: StatusAdditionalInfo
    FeesDetails:
        amount ?: string
        coin ?: string #/// <erc 20 
        gas ?: int #///< erc 20
        gas_price ?: string #///< erc20
        total_fee ?: string #///< erc20
    TransactionData:
        block_height: int
        coin: string
        confirmations ?: int
        fee_details: FeesDetails
        "from": string[]
        internal_id: string
        my_balance_change: string
        received_by_me: string
        spent_by_me: string
        timestamp: int
        to: string[]
        total_amount: string
        tx_hash: string
        tx_hex: string
    TransactionHistoryContents:
        "current_block": int
        "from_id" : string or nil
        limit: int
        skipped: int
        sync_status: StatusData
        transactions: TransactionData[]
        total: int
    TransactionHistoryAnswerSuccess:
        "result" : TransactionHistoryContents
        "coin" ?: string
        "human_timestamp" ?: string
    TransactionHistoryAnswerError:
        error: string
    WithdrawRequestParams:
        "coin": string
        "to": string
        "amount": string
        "max": bool
    WithdrawAnswerSuccess:
        "result": TransactionData
    WithdrawAnswerError:
        error: string
    BroadcastRequestParams:
        coin: string
        tx_hex: string
    BroadcastAnswerSuccess:
        tx_hash: string
    BroadcastAnswerError:
        error: string

export ElectrumRequestParams
export ElectrumAnswerSuccess
export ElectrumAnswerError
export BalanceRequestParams
export BalanceAnswerSuccess
export FeesDetails
export TransactionData
export TransactionHistoryContents
export TransactionHistoryRequestParams
export TransactionHistoryAnswerSuccess
export WithdrawAnswerSuccess
export WithdrawAnswerError
export `[]`
export `unsafeAccess`
export `unsafeOptAccess`
export `create`
export `isValid`

##! Type Declaration
type ElectrumAnswer = object
        success*: Option[ElectrumAnswerSuccess]
        error*:  Option[ElectrumAnswerError]

type BalanceAnswer* = object
       success*: Option[BalanceAnswerSuccess]
       error*: Option[BalanceAnswerError]

type MyTransactionHistoryAnswer* = object
       success*: Option[TransactionHistoryAnswerSuccess]
       error*: Option[TransactionHistoryAnswerError]

type WithdrawAnswer* = object
       success*: Option[WithdrawAnswerSuccess]
       error*: Option[WithdrawAnswerError]

type BroadcastAnswer* = object
        success*: Option[BroadcastAnswerSuccess]
        error*: Option[BroadcastAnswerError]

##! Local Functions
proc onProgressChanged(total, progress, speed: BiggestInt) =
  echo("Downloaded ", progress, " of ", total)
  echo("Current rate: ", speed div 1000, "kb/s")

proc templateRequest(jsonData: JsonNode, method_name: string) =
    jsonData["method"] = method_name.newJString
    jsonData["userpass"] = "atomic_dex_rpc_password".newJString

##! Global Function
proc rpcElectrum*(req: ElectrumRequestParams) : ElectrumAnswer =
    let jsonData = req.JsonNode
    templateRequest(jsonData, "electrum")
    try:
        let json = processPost(jsonData).parseJson()
        if json.isValid(ElectrumAnswerSuccess):
            result.success = some(ElectrumAnswerSuccess(json))
        elif json.isValid(ElectrumAnswerError):
            result.error = some(ElectrumAnswerError(json))
    except HttpRequestError as e:
        error "Got exception HttpRequestError: ", e.msg
        result.error = some(ElectrumAnswerError(%*{"error": e.msg}))


proc rpcBalance*(req: BalanceRequestParams) : BalanceAnswer =
    let jsonData = req.JsonNode
    templateRequest(jsonData, "my_balance")
    try:
        let json = processPost(jsonData).parseJson()
        if json.isValid(BalanceAnswerSuccess):
            result.success = some(BalanceAnswerSuccess(json))
        elif json.isValid(BalanceAnswerError):
            result.error = some(BalanceAnswerError(json))
    except HttpRequestError as e:
        error "Got exception HttpRequestError: ", e.msg
        result.error = some(BalanceAnswerError(%*{"error": e.msg}))


proc rpcMyTxHistory*(req: TransactionHistoryRequestParams): MyTransactionHistoryAnswer =
    let jsonData = req.JsonNode
    templateRequest(jsonData, "my_tx_history")
    try:
        let json = processPost(jsonData).parseJson()
        if json.isValid(TransactionHistoryAnswerSuccess):
            result.success = some(TransactionHistoryAnswerSuccess(json))
            var res = result.success.get().JsonNode
            res["coin"] = newJString(req["coin"].getStr)
        elif json.isValid(TransactionHistoryAnswerError):
            result.error = some(TransactionHistoryAnswerError(json))
    except HttpRequestError as e:
        error("Got exception HttpRequestError: ", e.msg)
        result.error = some(TransactionHistoryAnswerError(%*{"error": e.msg}))


proc rpcWithdraw*(req: WithdrawRequestParams): WithdrawAnswer = 
    let jsonData = req.JsonNode
    templateRequest(jsonData, "withdraw")
    try:
        let 
            json = processPost(jsonData).parseJson()
            finalJson = %*{"result": json}
        if finalJson.isValid(WithdrawAnswerSuccess):
            result.success = some(WithdrawAnswerSuccess(finalJson))
        elif json.isValid(WithdrawAnswerError):
            result.error = some(WithdrawAnswerError(json))
    except HttpRequestError as e:
        error("Got exception HttpRequestError: ", e.msg)
        result.error = some(WithdrawAnswerError(%*{"error": e.msg}))