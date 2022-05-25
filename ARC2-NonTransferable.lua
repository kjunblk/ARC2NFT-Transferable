------------------------------------------------------------------------------
-- Aergo Standard NFT Interface (Proposal) - 20210425
------------------------------------------------------------------------------

extensions["non_transferable"] = true

function revoke(tokenId)
  _typecheck(tokenId, 'str128')

  local owner = ownerOf(tokenId)
  assert(owner ~= nil, "ARC2: burn - nonexisting token")
  assert(isMinter(system.getSender()), "ARC2: only minter can revoke")

  _burn(tokenId)
end

abi.register(revoke)

