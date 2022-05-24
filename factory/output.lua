arc2_core = [[
------------------------------------------------------------------------------
-- Aergo Standard NFT Interface (Proposal) - 20210425
------------------------------------------------------------------------------

extensions = {}

-- A internal type check function
-- @type internal
-- @param x variable to check
-- @param t (string) expected type
local function _typecheck(x, t)
  if (x and t == 'address') then
    assert(type(x) == 'string', "address must be string type")
    -- check address length
    assert(52 == #x, string.format("invalid address length: %s (%s)", x, #x))
    -- check character
    local invalidChar = string.match(x, '[^123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]')
    assert(nil == invalidChar, string.format("invalid address format: %s contains invalid char %s", x, invalidChar or 'nil'))
  elseif (x and t == 'str128') then
    assert(type(x) == 'string', "str128 must be string type")
    -- check address length
    assert(#x <= 128, string.format("too long str128 length: %s", #x))
  elseif (x and t == 'uint') then
    -- check unsigned integer
    assert(type(x) == 'number', string.format("invalid type: %s != number", type(x)))
    assert(math.floor(x) == x, "the number must be an integer")
    assert(x >= 0, "the number must be 0 or positive")
  else
    -- check default lua types
    assert(type(x) == t, string.format("invalid type: %s != %s", type(x), t or 'nil'))
  end
end

address0 = '1111111111111111111111111111111111111111111111111111'


state.var {
  _name = state.value(),            -- string
  _symbol = state.value(),          -- string

  _num_burned = state.value(),      -- integer
  _last_index = state.value(),      -- integer
  _ids = state.map(),               -- integer -> str128
  _tokens = state.map(),            -- str128 -> { owner: address, approved: address }
  _balances = state.map(),          -- address -> integer

  -- Pausable
  _paused = state.value(),          -- boolean

  -- Blacklist
  _blacklist = state.map(),        -- address -> boolean

  -- NonTransable
  _nonTransferable = state.value() -- boolean
}

-- call this at constructor
local function _init(name, symbol)
  _typecheck(name, 'string')
  _typecheck(symbol, 'string')
  
  _name:set(name)
  _symbol:set(symbol)

  _last_index:set(0)
  _num_burned:set(0)
  _paused:set(false)

  if extensions["nontransferable"] then
    _nonTransferable:set(true)
  end

end

local function _callOnARC2Received(from, to, tokenId, ...)
  if system.isContract(to) then
    contract.call(to, "onARC2Received", system.getSender(), from, tokenId, ...)
  end
end

local function _exists(tokenId)
  return _tokens[tokenId] ~= nil
end

-- Get the token name
-- @type    query
-- @return  (string) name of this token
function name()
  return _name:get()
end

-- Get the token symbol
-- @type    query
-- @return  (string) symbol of this token
function symbol()
  return _symbol:get()
end

-- seo Transferable
function nonTransferable()
  return _nonTransferable:get()
end

-- Count of all NFTs
-- @type    query
-- @return  (integer) the number of non-fungible tokens on this contract
function totalSupply()
  return _last_index:get() - _num_burned:get()
end

-- Count of all NFTs assigned to an owner
-- @type    query
-- @param   owner  (address) a target address
-- @return  (integer) the number of NFT tokens of owner
function balanceOf(owner)
  return _balances[owner] or 0
end

-- Find the owner of an NFT
-- @type    query
-- @param   tokenId (str128) the NFT id
-- @return  (address) the address of the owner of the NFT, or nil if token does not exist
function ownerOf(tokenId)
  local token = _tokens[tokenId]
  if token == nil then
    return nil
  else
    return token["owner"]
  end
end

local function _mint(to, tokenId, ...)
  _typecheck(to, 'address')
  _typecheck(tokenId, 'str128')

  assert(not _paused:get(), "ARC2: paused contract")
  assert(not _blacklist[to], "ARC2: recipient is on blacklist")

  assert(not _exists(tokenId), "ARC2: mint - already minted token")

  local index = _last_index:get() + 1
  _last_index:set(index)
  _ids[tostring(index)] = tokenId

  local token = {
    owner = to
  }
  _tokens[tokenId] = token

  _balances[to] = (_balances[to] or 0) + 1

  contract.event("mint", to, tokenId)

  return _callOnARC2Received(nil, to, tokenId, ...)
end


local function _burn(tokenId)
  _typecheck(tokenId, 'str128')

  local owner = ownerOf(tokenId)

  assert(not _paused:get(), "ARC2: paused contract")
  assert(not _blacklist[owner], "ARC2: owner is on blacklist")

  local index,_ = findToken({contains=tokenId}, 0)
  assert(index ~= nil and index > 0, "burn: token not found")
  -- _ids[tostring(index)] = nil
  _ids:delete(tostring(index))

  _tokens:delete(tokenId)
  _balances[owner] = _balances[owner] - 1

  _num_burned:set(_num_burned:get() + 1)

  contract.event("burn", owner, tokenId)
end


local function _transfer(from, to, tokenId, ...)
-- seo Transferable
  assert(not _nonTransferable:get(), "ARC2: non-transferable contract")
  assert(not _paused:get(), "ARC2: paused contract")
  assert(not _blacklist[from], "ARC2: sender is on blacklist")
  assert(not _blacklist[to], "ARC2: recipient is on blacklist")

  _balances[from] = _balances[from] - 1
  _balances[to] = (_balances[to] or 0) + 1

--[[
  local token = _tokens[tokenId]
  token["owner"] = to
  table.remove(token, "approved")  -- clear approval
  _tokens[tokenId] = token
] ]

  -- this will also clear approvals from the previous owner
  local token = {
    owner = to
  }
  _tokens[tokenId] = token

  return _callOnARC2Received(from, to, tokenId, ...)
end


-- Transfer a token
-- @type    call
-- @param   to      (address) a receiver's address
-- @param   tokenId (str128) the NFT token to send
-- @param   ...     (Optional) addtional data, MUST be sent unaltered in call to 'onARC2Received' on 'to'
-- @event   transfer(from, to, tokenId)
function transfer(to, tokenId, ...)
  _typecheck(to, 'address')
  _typecheck(tokenId, 'str128')

  local from = system.getSender()

  local owner = ownerOf(tokenId)
  assert(owner ~= nil, "ARC2: transfer - nonexisting token")
  assert(from == owner, "ARC2: transfer of token that is not own")

  contract.event("transfer", from, to, tokenId, nil)

  return _transfer(from, to, tokenId, ...)
end


function nextToken(prev_index)
  _typecheck(prev_index, 'uint')

  local index = prev_index
  local last_index = _last_index:get()
  local tokenId

  if index >= last_index then
    return nil, nil
  end

  while tokenId == nil and index < last_index
  do
    index = index + 1
    tokenId = _ids[tostring(index)]

  if index == last_index and tokenId == nil then
     index = nil
  end

  return index, tokenId
end

-- retrieve the first token found that mathes the query
-- the query is a table that can contain these fields:
--   owner    - the owner of the token (address)
--   contains - check if the tokenId contains this string
--   pattern  - check if the tokenId matches this Lua regex pattern
-- the prev_index must be 0 in the first call
-- for the next calls, just inform the returned index from the last call
-- return value: 2 variables: index and tokenId
-- if no token is found with the given query, it returns (nil, nil)
--
function findToken(query, prev_index)
  _typecheck(query, 'table')
  _typecheck(prev_index, 'uint')

  local contains = query["contains"]
  if contains then
    query["pattern"] = escape(contains)
  end

  local index = prev_index
  local last_index = _last_index:get()
  local tokenId, owner

  if index >= last_index then
    return nil, nil
  end

  while tokenId == nil and index < last_index
  do
    index = index + 1
    tokenId = _ids[tostring(index)]
    if not token_matches(tokenId, query) then
      tokenId = nil
    end
  end

  if index == last_index and tokenId == nil then
    index = nil
  end

  return index, tokenId
end

local function token_matches(tokenId, query)

  if tokenId == nil then
    return false
  end

  local user = query["owner"]
  local pattern = query["pattern"]

  if user then
    local owner = ownerOf(tokenId)
    if owner ~= user then
      return false
    end
  end

  if pattern then
    if not tokenId:match(pattern) then
      return false
    end
  end

  return true
end

local function escape(str)
  return str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", function(c) return "%" .. c end)
end


-- returns a JSON string containing the list of ARC2 extensions
-- that were included on the contract
function arc2_extensions()
  local list = {}
  for name,_ in pairs(extensions) do
    table.insert(list, name)
  end
  return json.encode(list)
end


abi.register(transfer, arc2_extensions)
-- seo nonTransferable
abi.register_view(name, symbol, nonTransferable, balanceOf, ownerOf, totalSupply, nextToken, findToken)
]]

arc2_burnable = [[
------------------------------------------------------------------------------
-- Aergo Standard NFT Interface (Proposal) - 20210425
------------------------------------------------------------------------------

extensions["burnable"] = true

function burn(tokenId)
  _typecheck(tokenId, 'str128')

  local owner = ownerOf(tokenId)
  assert(owner ~= nil, "ARC2: burn - nonexisting token")
  assert(system.getSender() == owner, "ARC2: cannot burn a token that is not own")

  _burn(tokenId)
end

abi.register(burn)
]]

arc2_mintable = [[
------------------------------------------------------------------------------
-- Aergo Standard NFT Interface (Proposal) - 20210425
------------------------------------------------------------------------------

extensions["mintable"] = true

state.var {
  -- mintable
  _minter = state.map(),       -- address -> boolean
  _max_supply = state.value()  -- integer
}

-- set Max Supply
-- @type    internal
-- @param   amount   (integer) amount of mintable tokens

local function _setMaxSupply(amount)
  _typecheck(amount, 'uint')
  _max_supply:set(amount)
end

-- Indicate if an account is a minter
-- @type    query
-- @param   account  (address)
-- @return  (bool) true/false

function isMinter(account)
  _typecheck(account, 'address')

  return (account == _creator:get()) or (_minter[account]==true)
end

-- Add an account to minters
-- @type    call
-- @param   account  (address)
-- @event   addMinter(account)

function addMinter(account)
  _typecheck(account, 'address')

  assert(system.getSender() == _creator:get(), "ARC2: only the contract owner can add a minter")

  _minter[account] = true

  contract.event("addMinter", account)
end

-- Remove an account from minters
-- @type    call
-- @param   account  (address)
-- @event   removeMinter(account)

function removeMinter(account)
  _typecheck(account, 'address')

  assert(system.getSender() == _creator:get(), "ARC2: only the contract owner can remove a minter")
  assert(account ~= _creator:get(), "ARC2: the contract owner is always a minter")
  assert(isMinter(account), "ARC2: not a minter")

  _minter:delete(account)

  contract.event("removeMinter", account)
end

-- Renounce the Minter Role of TX sender
-- @type    call
-- @event   removeMinter(TX sender)

function renounceMinter()
  local sender = system.getSender()
  assert(sender ~= _creator:get(), "ARC2: contract owner can't renounce minter role")
  assert(isMinter(sender), "ARC2: only minter can renounce minter role")

  _minter:delete(sender)

  contract.event("removeMinter", sender)
end

-- Mint a new non-fungible token
-- @type    call
-- @param   to       (address) recipient's address
-- @param   tokenId  (str128) the NFT id
-- @param   ...      additional data, is sent unaltered in call to 'tokensReceived' on 'to'
-- @return  value returned from 'tokensReceived' callback, or nil
-- @event   mint(to, tokenId)

function mint(to, tokenId, ...)
  assert(isMinter(system.getSender()), "ARC2: only minter can mint")
  assert(not _max_supply:get() or (totalSupply() + 1) <= _max_supply:get(), "ARC2: totalSupply is over MaxSupply")

  return _mint(to, tokenId, ...)
end

-- return Max Supply
-- @type    query
-- @return  amount   (integer) amount of tokens to mint

function maxSupply()
  return _max_supply:get() or 0
end

abi.register(mint, addMinter, removeMinter, renounceMinter)
abi.register_view(isMinter, maxSupply)
]]

arc2_pausable = [[
------------------------------------------------------------------------------
-- Aergo Standard Token Interface (Proposal) - 20211028
-- Pausable
------------------------------------------------------------------------------

extensions["pausable"] = true

state.var {
  -- pausable
  _pauser = state.map(),   -- address -> boolean
}


-- Indicate an account has the Pauser Role
-- @type    query
-- @param   account  (address)
-- @return  (bool) true/false

function isPauser(account)
  _typecheck(account, 'address')

  return (account == _creator:get()) or (_pauser[account]==true)
end


-- Grant the Pauser Role to an account
-- @type    call
-- @param   account  (address)
-- @event   addPauser(account)

function addPauser(account)
  _typecheck(account, 'address')

  assert(system.getSender() == _creator:get(), "ARC2: only contract owner can approve pauser role")

  _pauser[account] = true

  contract.event("addPauser", account)
end


-- Removes the Pauser Role form an account
-- @type    call
-- @param   account  (address)
-- @event   removePauser(account)

function removePauser(account)
  _typecheck(account, 'address')

  assert(system.getSender() == _creator:get(), "ARC2: only owner can remove pauser role")
  assert(isPauser(account), "ARC2: only pauser can be removed pauser role")

  _pauser[account] = nil

  contract.event("removePauser", account)
end


-- Renounce the graned Pauser Role of TX sender
-- @type    call
-- @event   removePauser(TX sender)

function renouncePauser()
  assert(system.getSender() ~= _creator:get(), "ARC2: owner can't renounce pauser role")
  assert(isPauser(system.getSender()), "ARC2: only pauser can renounce pauser role")

  _pauser[system.getSender()] = nil

  contract.event("removePauser", system.getSender())
end


-- Indecate if the contract is paused
-- @type    query
-- @return  (bool) true/false

function paused()
  return (_paused:get() == true)
end


-- Trigger stopped state
-- @type    call
-- @event   pause(TX sender)

function pause()
  assert(not _paused:get(), "ARC2: contract is paused")
  assert(isPauser(system.getSender()), "ARC2: only pauser can pause")

  _paused:set(true)

  contract.event("pause", system.getSender())
end


-- Return to normal state
-- @type    call
-- @event   unpause(TX sender)

function unpause()
  assert(_paused:get(), "ARC2: contract is unpaused")
  assert(isPauser(system.getSender()), "ARC2: only pauser can unpause")

  _paused:set(false)

  contract.event("unpause", system.getSender())
end


abi.register(pause, unpause, removePauser, renouncePauser, addPauser)
abi.register_view(paused, isPauser)
]]

arc2_blacklist = [[
------------------------------------------------------------------------------
-- Aergo Standard Token Interface (Proposal) - 20211028
-- Blacklist
------------------------------------------------------------------------------

extensions["blacklist"] = true

-- Add accounts to blacklist.
-- @type    call
-- @param   account_list    (list of address)
-- @event   addToBlacklist(account_list)

function addToBlacklist(account_list)
  assert(system.getSender() == _creator:get(), "ARC2: only owner can blacklist accounts")

  for i = 1, #account_list do
    _typecheck(account_list[i], 'address')
    _blacklist[account_list[i] ] = true
  end

  contract.event("addToBlacklist", account_list)
end


-- removes accounts from blacklist
-- @type    call
-- @param   account_list    (list of address)
-- @event   removeFromBlacklist(account_list)

function removeFromBlacklist(account_list)
  assert(system.getSender() == _creator:get(), "ARC2: only owner can blacklist accounts")

  for i = 1, #account_list do
    _typecheck(account_list[i], 'address')
    _blacklist[account_list[i] ] = nil
  end

  contract.event("removeFromBlacklist", account_list)
end


-- Retrun true when an account is on blacklist
-- @type    query
-- @param   account   (address)

function isOnBlacklist(account)
  _typecheck(account, 'address')

  return _blacklist[account] == true
end


abi.register(addToBlacklist,removeFromBlacklist)
abi.register_view(isOnBlacklist)
]]

arc2_approval = [[
------------------------------------------------------------------------------
-- Aergo Standard NFT Interface (Proposal) - 20210425
------------------------------------------------------------------------------

extensions["approval"] = true


state.var {
  _operatorApprovals = state.map(), -- address/address -> bool
}


-- Approve `to` to operate on `tokenId`
-- Emits an approve event
local function _approve(to, tokenId)
  local token = _tokens[tokenId]
  local owner = token["owner"]
  assert(not _paused:get(), "ARC2: paused contract")
  assert(not _blacklist[owner], "ARC2: owner is on blacklist")
  if to == nil then
    table.remove(token, "approved")
  else
    assert(not _blacklist[to], "ARC2: user is on blacklist")
    token["approved"] = to
  end
  _tokens[tokenId] = token
  contract.event("approve", owner, to, tokenId)
end


-- Change or reaffirm the approved address for an NFT
-- @type    call
-- @param   to          (address) the new approved NFT controller
-- @param   tokenId     (str128) the NFT token to approve
-- @event   approve(owner, to, tokenId)
function approve(to, tokenId)
  _typecheck(to, 'address')
  _typecheck(tokenId, 'str128')

  local owner = ownerOf(tokenId)
  assert(owner ~= nil, "ARC2: approve - nonexisting token")
  assert(owner ~= to, "ARC2: approve - to current owner")
  assert(system.getSender() == owner or isApprovedForAll(owner, system.getSender()), 
    "ARC2: approve - caller is not owner nor approved for all")

  _approve(to, tokenId)
end

-- Get the approved address for a single NFT
-- @type    query
-- @param   tokenId  (str128) the NFT token to find the approved address for
-- @return  (address) the approved address for this NFT, or nil
function getApproved(tokenId)
  _typecheck(tokenId, 'str128')
  local token = _tokens[tokenId]
  assert(token ~= nil, "ARC2: getApproved - nonexisting token")
  return token["approved"]
end


-- Allow operator to control all sender's token
-- @type    call
-- @param   operator  (address) a operator's address
-- @param   approved  (boolean) true if the operator is approved, false to revoke approval
-- @event   approvalForAll(owner, operator, approved)
function setApprovalForAll(operator, approved)
  _typecheck(operator, 'address')
  _typecheck(approved, 'boolean')

  local owner = system.getSender()

  assert(not _paused:get(), "ARC2: paused contract")
  assert(not _blacklist[owner], "ARC2: owner is on blacklist")
  if approved then
    assert(not _blacklist[operator], "ARC2: operator is on blacklist")
  end

  assert(operator ~= owner, "ARC2: setApprovalForAll - to caller")

  _operatorApprovals[owner .. '/' .. operator] = approved

  contract.event("approvalForAll", owner, operator, approved)
end


-- Get allowance from owner to spender
-- @type    query
-- @param   owner       (address) owner's address
-- @param   operator    (address) allowed address
-- @return  (bool) true/false
function isApprovedForAll(owner, operator)
  return _operatorApprovals[owner .. '/' .. operator] or false
end


-- Transfer a token of 'from' to 'to'
-- @type    call
-- @param   from    (address) a sender's address
-- @param   to      (address) a receiver's address
-- @param   tokenId (str128) the NFT token to send
-- @param   ...     (Optional) addtional data, MUST be sent unaltered in call to 'onARC2Received' on 'to'
-- @event   transfer(from, to, tokenId)
function transferFrom(from, to, tokenId, ...)
  _typecheck(from, 'address')
  _typecheck(to, 'address')
  _typecheck(tokenId, 'str128')

  local owner = ownerOf(tokenId)
  assert(owner ~= nil, "ARC2: transferFrom - nonexisting token")
  assert(from == owner, "ARC2: transferFrom - transfer of token that is not own")

  local operator = system.getSender()
  assert(operator == owner or getApproved(tokenId) == operator or isApprovedForAll(owner, operator), "ARC2: transferFrom - caller is not owner nor approved")

  contract.event("transfer", from, to, tokenId, operator)

  return _transfer(from, to, tokenId, ...)
end


abi.register(approve, setApprovalForAll, transferFrom)
abi.register_view(getApproved, isApprovedForAll)
]]

arc2_nontransferable = [[
%nontransferable%
]]

arc2_constructor = [[
state.var {
  _creator = state.value()
}

function constructor(name, symbol, initial_supply, max_supply, owner)
  _init(name, symbol)
  _creator:set(owner)
  if initial_supply then
    for _,tokenId in ipairs(initial_supply) do
      _mint(owner, tokenId)
    end
  end
  if max_supply then
    _setMaxSupply(max_supply)
  end
end
]]

function new_arc2_nft(name, symbol, initial_supply, options, owner)

  if options == nil or options == '' then
    options = {}
  end

  if owner == nil or owner == '' then
    owner = system.getSender()
  end

  local contract_code = arc2_core .. arc2_constructor

  if options["burnable"] then
    contract_code = contract_code .. arc2_burnable
  end
  if options["mintable"] then
    contract_code = contract_code .. arc2_mintable
  end
  if options["pausable"] then
    contract_code = contract_code .. arc2_pausable
  end
  if options["blacklist"] then
    contract_code = contract_code .. arc2_blacklist
  end
  if options["approval"] then
    contract_code = contract_code .. arc2_approval
  end
  if options["nontransferable"] then
    contract_code = contract_code .. arc2_nontransferable
  end

  local max_supply = options["max_supply"]
  if max_supply then
    assert(options["mintable"], "max_supply is only available with the mintable extension")
    max_supply = tonumber(max_supply)
    if initial_supply then
      assert(max_supply >= #initial_supply, "the max supply must be bigger than the initial supply count")
    end
  end

  local address = contract.deploy(contract_code, name, symbol, initial_supply, max_supply, owner)

  contract.event("new_arc2_token", address)

  return address
end

abi.register(new_arc2_token)
