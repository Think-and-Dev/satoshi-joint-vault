// Import standard Motoko modules
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";

import Icrc1Ledger "canister:icrc1_ledger_canister";

// Define the shareable transaction type
type Transaction = {
  id : Nat;
  amount : Nat; // Amount in ckBTC
  recipient : Principal; // Transaction recipient
  approvedBy : [Principal]; // List of signers who have approved the transaction
};

  type InternalTransaction = {
    id : Nat;
    amount : Nat; // Amount in ckBTC
    recipient : Principal; // Transaction recipient
    approvedBy: Buffer.Buffer<Principal>; 
  };
// Global state of the canister
actor SJVault {
  // List of authorized signers
  var signers : [Principal] = [];

  // Minimum number of signatures required to approve a transaction
  var signatureThreshold : Nat = 2;

  // List of pending transactions
  var pendingTransactions : Buffer.Buffer<InternalTransaction> = Buffer.Buffer<InternalTransaction>(1);

  // ID for transactions
  var nextTransactionId : Nat = 0;

  // Initialize the vault
  public func initVault(initialSigners : [Principal], threshold : Nat) {
    assert (
      Array.size(initialSigners) >= threshold
    );
    signers := initialSigners;
    signatureThreshold := threshold;
  };

  // Add a new signer to the vault
  public func addSigner(newSigner : Principal) : async () {
    if (Array.indexOf<Principal>(newSigner, signers, Principal.equal) == null) {
      signers := Array.append<Principal>(signers, [newSigner]);
    };
  };

  // Remove an existing signer
  public func removeSigner(signer : Principal) : async () {
    signers := Array.filter<Principal>(signers, func(s) { s != signer });
  };

  // Create a new transaction (only authorized signers can create)
  public shared (msg) func createTransaction(amount : Nat, recipient : Principal) : async Nat {
    assert (
      Array.indexOf<Principal>(msg.caller, signers, Principal.equal) != null
    );

    let initialApprovers = Buffer.Buffer<Principal>(1);
    initialApprovers.add(msg.caller);

    let newTransaction = {
      id = nextTransactionId;
      amount = amount;
      recipient = recipient;
      approvedBy = initialApprovers;
    };

    pendingTransactions.add(newTransaction);
    nextTransactionId := nextTransactionId + 1;

    return newTransaction.id;
  };

  private func findTransactionIndex(transactionId: Nat) : ?Nat {
    var i: Nat = 0;
    for (t in Buffer.toArray(pendingTransactions).keys()) {
      var tx = pendingTransactions.get(t);
      if (tx.id == transactionId) {
        return ?i;
      };
      i += 1;
    };
    return null;
  };

  // Approve a transaction by a signer
  public shared (msg) func approveTransaction(transactionId : Nat) : async Bool {
    let caller = msg.caller;

    // Find the pending transaction
    var foundIndex : ?Nat = findTransactionIndex(transactionId);
  
    switch (foundIndex) {
      case null {
        // If transaction is not found, return false
        return false;  // Transacción no encontrada
      };
      case (?i) {
        let transaction = pendingTransactions.get(i);
        // Check if the signer has already approved
        if (Buffer.contains<Principal>( transaction.approvedBy,caller, Principal.equal)) {
          return false;
        };

        // Update the transaction in the pending list
        transaction.approvedBy.add(caller);

        // Check if the transaction has reached the required number of signatures
        if (transaction.approvedBy.size() >= signatureThreshold) {
          executeTransaction(transaction,i);
          return true;
        };

        return false;
        }
        }
  };

  // Execute the transaction (once the signature threshold is reached)
  private func executeTransaction(tx : InternalTransaction, foundIndex: Nat) : () {
    // Logic to transfer ckBTC to the recipient (tx.recipient) for the amount tx.amount
    // This would be the connection to ckBTC, which would handle the token transfer.
    Debug.print(
      "Transferring "
      # debug_show (args.amount)
      # " tokens to account"
      # debug_show (args.toAccount)
    );

    let transferArgs : Icrc1Ledger.TransferArg = {
      // can be used to distinguish between transactions
      memo = null;
      // the amount we want to transfer
      amount = tx.amount;
      // we want to transfer tokens from the default subaccount of the canister
      from_subaccount = null;
      // if not specified, the default fee for the canister is used
      fee = null;
      to = tx.recipient;
      // a timestamp indicating when the transaction was created by the caller; if it is not specified by the caller then this is set to the current ICP time
      created_at_time = null;
    };

    try {
      // initiate the transfer
      let transferResult = await Icrc1Ledger.icrc1_transfer(transferArgs);

      // check if the transfer was successful
      switch (transferResult) {
        case (#Err(transferError)) {
          return #err("Couldn't transfer funds:\n" # debug_show (transferError));
        };
        case (#Ok(blockIndex)) { return #ok blockIndex };
      };
    } catch (error : Error) {
      // catch any errors that might occur during the transfer
      return #err("Reject message: " # Error.message(error));
    };

    // Remove the transaction from the pending list
    let _ = pendingTransactions.remove(foundIndex);
    return;
  };

  // Get all pending transactions
  public query func getPendingTransactions() : async [Transaction] {
    var result: [Transaction] = [];
    
    for (i in Buffer.toArray(pendingTransactions).keys()) {
        let internalTx = pendingTransactions.get(i);
        let tx: Transaction = {
          id = internalTx.id;
          amount = internalTx.amount;
          recipient = internalTx.recipient;
          approvedBy = Buffer.toArray(internalTx.approvedBy);  
        };
        result := Array.append(result, [tx]);  
    };
    
    return result;
  };
  // Get the current signers
  public query func getSigners() : async [Principal] {
    return signers;
  };

  // Get the current signature threshold
  public query func getSignatureThreshold() : async Nat {
    return signatureThreshold;
  };
};
