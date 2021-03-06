// SPDX-License-Identifier: MIT

pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./PepemonFactory.sol";
import "./CardBase.sol";

contract Deck is ERC721, ERC1155Holder, Ownable {
    using SafeMath for uint256;

    struct Decks {
        uint256 battleCardId;
        uint256 actionCardCount;
        mapping(uint256 => ActionCardType) actionCardTypes;
        uint256[] actionCardTypeList;
    }

    struct ActionCardType {
        uint256 actionCardTypeId;
        uint256 count;
        uint256 pointer;
        bool isEntity;
    }

    struct ActionCardRequest {
        uint256 actionCardTypeId;
        uint256 amount;
    }

    uint8 public MAX_ACTION_CARDS;

    uint256 nextDeckId;
    address public battleCardAddress;
    address public actionCardAddress;

    mapping(uint256 => Decks) public decks;

    constructor() ERC721("Pepedeck", "Pepedeck") {
        nextDeckId = 1;
        MAX_ACTION_CARDS = 60;
    }

    function setBattleCardAddress(address _battleCardAddress) public onlyOwner {
        battleCardAddress = _battleCardAddress;
    }

    function setActionCardAddress(address _actionCardAddress) public onlyOwner {
        actionCardAddress = _actionCardAddress;
    }

    function setMaxActionCards(uint8 _maxActionCards) public onlyOwner {
        MAX_ACTION_CARDS = _maxActionCards;
    }

    function createDeck() public {
        _safeMint(msg.sender, nextDeckId);
    }

    function addBattleCard(uint256 _deckId, uint256 _battleCardId) public {
        require(PepemonFactory(battleCardAddress).balanceOf(msg.sender, _battleCardId) >= 1, "Don't own battle card");
        require(_battleCardId != decks[_deckId].battleCardId, "Card already in deck");

        uint256 oldBattleCardId = decks[_deckId].battleCardId;
        decks[_deckId].battleCardId = _battleCardId;

        PepemonFactory(battleCardAddress).safeTransferFrom(msg.sender, address(this), _battleCardId, 1, "");

        returnBattleCard(oldBattleCardId);
    }

    function removeBattleCard(uint256 _deckId) public {
        require(ownerOf(_deckId) == msg.sender, "Not your deck");

        uint256 oldBattleCardId = decks[_deckId].battleCardId;

        decks[_deckId].battleCardId = 0;

        returnBattleCard(oldBattleCardId);
    }

    function addActionCards(uint256 _deckId, ActionCardRequest[] memory _actionCards) public {
        for (uint256 i = 0; i < _actionCards.length; i++) {
            addActionCard(_deckId, _actionCards[i].actionCardTypeId, _actionCards[i].amount);
        }
    }

    function removeActionCards(uint256 _deckId, ActionCardRequest[] memory _actionCards) public {
        for (uint256 i = 0; i < _actionCards.length; i++) {
            removeActionCard(_deckId, _actionCards[i].actionCardTypeId, _actionCards[i].amount);
        }
    }

    // INTERNALS
    function addActionCard(
        uint256 _deckId,
        uint256 _actionCardTypeId,
        uint256 _amount
    ) internal {
        require(MAX_ACTION_CARDS >= decks[_deckId].actionCardCount.add(_amount), "Deck is full");
        require(
            PepemonFactory(actionCardAddress).balanceOf(msg.sender, _actionCardTypeId) >= _amount,
            "You don't have enough of this card"
        );

        if (!decks[_deckId].actionCardTypes[_actionCardTypeId].isEntity) {
            decks[_deckId].actionCardTypes[_actionCardTypeId] = ActionCardType({
                actionCardTypeId: _actionCardTypeId,
                count: _amount,
                pointer: decks[_deckId].actionCardTypeList.length,
                isEntity: true
            });

            // Prepend the ID to the list
            decks[_deckId].actionCardTypeList.push(_actionCardTypeId);
        } else {
            ActionCardType storage actionCard = decks[_deckId].actionCardTypes[_actionCardTypeId];
            actionCard.count = actionCard.count.add(_amount);
        }

        decks[_deckId].actionCardCount = decks[_deckId].actionCardCount.add(_amount);

        PepemonFactory(actionCardAddress).safeTransferFrom(msg.sender, address(this), _actionCardTypeId, _amount, "");
    }

    function removeActionCardTypeFromDeck(uint256 _deckId, uint256 _actionCardTypeId) internal {
        Decks storage deck = decks[_deckId];
        ActionCardType storage actionCardType = decks[_deckId].actionCardTypes[_actionCardTypeId];

        uint256 cardTypeToRemove = actionCardType.pointer;

        if (deck.actionCardTypeList.length > 1 && cardTypeToRemove != deck.actionCardTypeList.length - 1) {
            // last card type in list
            uint256 rowToMove = deck.actionCardTypeList[deck.actionCardTypeList.length - 1];

            // swap delete row with row to move
            decks[_deckId].actionCardTypes[rowToMove].pointer = cardTypeToRemove;
        }

        decks[_deckId].actionCardTypeList.pop();
        delete decks[_deckId].actionCardTypes[cardTypeToRemove];
    }

    function removeActionCard(
        uint256 _deckId,
        uint256 _actionCardTypeId,
        uint256 _amount
    ) internal {
        ActionCardType storage actionCardList = decks[_deckId].actionCardTypes[_actionCardTypeId];
        actionCardList.count = actionCardList.count.sub(_amount);

        decks[_deckId].actionCardCount = decks[_deckId].actionCardCount.sub(_amount);

        if (actionCardList.count == 0) {
            decks[_deckId].actionCardTypeList.pop();
            delete decks[_deckId].actionCardTypes[_actionCardTypeId];
        }

        PepemonFactory(actionCardAddress).safeTransferFrom(address(this), msg.sender, _actionCardTypeId, _amount, "");
    }

    function returnBattleCard(uint256 _battleCardId) internal {
        if (_battleCardId != 0) {
            PepemonFactory(battleCardAddress).safeTransferFrom(address(this), msg.sender, _battleCardId, 1, "");
        }
    }

    // VIEWS
    function getBattleCardForDeck(uint256 _deckId) public view returns (uint256) {
        return decks[_deckId].battleCardId;
    }

    function getCardTypesInDeck(uint256 _deckId) public view returns (uint256[] memory) {
        Decks storage deck = decks[_deckId];

        uint256[] memory actionCardTypes = new uint256[](deck.actionCardTypeList.length);

        for (uint256 i = 0; i < deck.actionCardTypeList.length; i++) {
            actionCardTypes[i] = deck.actionCardTypeList[i];
        }

        return actionCardTypes;
    }

    function getCountOfCardTypeInDeck(uint256 _deckId, uint256 _cardTypeId) public view returns (uint256) {
        return decks[_deckId].actionCardTypes[_cardTypeId].count;
    }

    modifier sendersDeck(uint256 _deckId) {
        require(msg.sender == ownerOf(_deckId));
        _;
    }
}
