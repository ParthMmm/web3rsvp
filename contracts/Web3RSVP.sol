// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Web3RSVP {

    event NewEventCreated(
    bytes32 eventID,
    address creatorAddress,
    uint256 eventTimestamp,
    uint256 maxCapacity,
    uint256 deposit,
    string eventDataCID
);

    event NewRSVP(bytes32 eventID, address attendeeAddress);

    event ConfirmedAttendee(bytes32 eventID, address attendeeAddress);

    event DepositsPaidOut(bytes32 eventID);


   struct CreateEvent {
       bytes32 eventId;
       string eventDataCID;
       address eventOwner;
       uint256 eventTimestamp;
       uint256 deposit;
       uint256 maxCapacity;
       address[] confirmedRSVPs;
       address[] claimedRSVPs;
       bool paidOut;
   }

    mapping(bytes32 => CreateEvent) public idToEvent;

    function createNewEvent(
    uint256 eventTimestamp,
    uint256 deposit,
    uint256 maxCapacity,
    string calldata eventDataCID
    ) external {
        // generate an eventID based on other things passed in to generate a hash
        bytes32 eventId = keccak256(
            abi.encodePacked(
                msg.sender,
                address(this),
                eventTimestamp,
                deposit,
                maxCapacity
            )
        );

        address[] memory confirmedRSVPs;
        address[] memory claimedRSVPs;


        // this creates a new CreateEvent struct and adds it to the idToEvent mapping
        idToEvent[eventId] = CreateEvent(
            eventId,
            eventDataCID,
            msg.sender,
            eventTimestamp,
            deposit,
            maxCapacity,
            confirmedRSVPs,
            claimedRSVPs,
            false
        );

        emit NewEventCreated(
            eventId,
            msg.sender,
            eventTimestamp,
            maxCapacity,
            deposit,
            eventDataCID
        );
    }

    function createNewRSVP(bytes32 eventId) external payable{
        // look up event from our mapping
        CreateEvent storage myEvent = idToEvent[eventId];

        // transfer deposit to our contract / require that they send in enough ETH to cover
        require(msg.value == myEvent.deposit, "NOT ENOUGH DEPOSIT");

        //require that the event hasn't already happened (<evenTimestamp)
        require(block.timestamp <= myEvent.eventTimestamp, "EVENT HAS ALREADY HAPPENED");
        
        //make sure event is under max capacity
        require(myEvent.confirmedRSVPs.length < myEvent.maxCapacity, "MAX CAPACITY REACHED");

        //require that msg.send isn't already in the confirmedRSVPs array
        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            require(myEvent.confirmedRSVPs[i] != msg.sender, "YOU ALREADY RSVPED");
        }

        myEvent.confirmedRSVPs.push(payable(msg.sender));

        emit NewRSVP(eventId, msg.sender);
    }


    function confirmAttendee(bytes32 eventId, address attendee) public{

        //look up event from our struct using the eventId
        CreateEvent storage myEvent = idToEvent[eventId];

        //requre that msg.sender is the event owner
        require(msg.sender == myEvent.eventOwner, "YOU ARE NOT THE OWNER OF THIS EVENT");

        //require the attendee trying to check in actually RSVP'd for this event
        address rsvpConfirm;

        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            if (myEvent.confirmedRSVPs[i] == attendee) {
                rsvpConfirm = myEvent.confirmedRSVPs[i];
            }
        }

        require(rsvpConfirm == attendee, "YOU HAVE NOT RSVPED FOR THIS EVENT");

        //require that the attendee isn't already in the claimedRSVPs array
        for (uint8 i = 0; i < myEvent.claimedRSVPs.length; i++) {
            require(myEvent.claimedRSVPs[i] != attendee, "YOU ALREADY CLAIMED THIS RSVP");
        }

        //require that deposits are not already claimed by the event owner
        require(myEvent.paidOut == false, "DEPOSITS ALREADY PAID OUT");

        //add attendee to claimedRSVPs array
        myEvent.claimedRSVPs.push(attendee);

        //send eth back to staker
        (bool sent,) = attendee.call{value: myEvent.deposit}("");


        //if this fails, remove user from array of claimed RSVPS
        if(!sent){
            myEvent.claimedRSVPs.pop();
        }

        require(sent, "Failed to send Ether to attendee");

        emit ConfirmedAttendee(eventId, attendee);
    }


    function confirmAllAttendees(bytes32 eventId) external{

        //look up event from our struct with the eventId
        CreateEvent memory myEvent = idToEvent[eventId];

        require(msg.sender == myEvent.eventOwner, "YOU ARE NOT THE OWNER OF THIS EVENT");

        //confirm each attendee in the rsvp array
        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            confirmAttendee(eventId, myEvent.confirmedRSVPs[i]);
        }
    }

    function withdrawUnclaimedDeposits(bytes32 eventId) external{
        //look up event
        CreateEvent memory myEvent = idToEvent[eventId];


        // check that the paidOut boolean still equals false AKA the money hasn't already been paid out
        require(!myEvent.paidOut, "ALREADY PAID");

        //check if it's been more 7 days past myEvent.eventTimestamp
        require(
            block.timestamp >= (myEvent.eventTimestamp + 7 days), "TOO EARLY"
        );

        //only event owner can withdra
        require(msg.sender == myEvent.eventOwner, "YOU ARE NOT THE OWNER OF THIS EVENT");

        //calculate how many people didn't claim by comparing
        uint256 unclaimed = myEvent.confirmedRSVPs.length - myEvent.claimedRSVPs.length;
        uint256 payout = unclaimed * myEvent.deposit;


        //mark as paid before sending to avoid reentrancy attack
        myEvent.paidOut = true;

        // send the payout to the owner
        (bool sent, ) = msg.sender.call{value: payout}("");

        // if this fails
        if (!sent) {
            myEvent.paidOut == false;
        }

        require(sent, "Failed to send Ether");

        emit DepositsPaidOut(eventId);
    }

}

