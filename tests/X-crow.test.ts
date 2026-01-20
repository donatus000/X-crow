import { describe, it, expect, beforeEach } from "vitest";
import { tx } from "@hirosystems/clarinet-sdk";
import {
  bufferCV,
  type ClarityValue,
  cvToJSON,
  listCV,
  standardPrincipalCV,
  stringAsciiCV,
  uintCV,
} from "@stacks/transactions";

const CONTRACT_NAME = "X-crow";
const RATE_LIMIT_BLOCKS = 10;
const REFUND_TIMEOUT_BLOCKS = 144;
const LARGE_WITHDRAW_THRESHOLD = 1_000_000n;

const accounts = simnet.getAccounts();
const client = accounts.get("wallet_1")!;
const freelancer = accounts.get("wallet_2")!;
const arbiter = accounts.get("wallet_3")!;
const signer = accounts.get("wallet_4")!;

const mineCall = (
  sender: string,
  method: string,
  args: ClarityValue[] = [],
) =>
  simnet.mineBlock([tx.callPublicFn(CONTRACT_NAME, method, args, sender)])[0];

const readOnly = (
  method: string,
  args: ClarityValue[] = [],
  sender: string = client,
) =>
  simnet.callReadOnlyFn(CONTRACT_NAME, method, args, sender);

const advanceBlocks = (count = RATE_LIMIT_BLOCKS) => {
  simnet.mineEmptyBlocks(count);
};

const unwrapClarityValue = (value: any): any => {
  if (value && typeof value === "object" && "value" in value) {
    return unwrapClarityValue(value.value);
  }
  return value;
};

const unwrapOkJSON = (result: any) => {
  const json = cvToJSON(result);
  expect(json.success).toBe(true);
  return unwrapClarityValue(json.value);
};

const unwrapErrCode = (result: any) => {
  const json = cvToJSON(result);
  expect(json.success).toBe(false);
  return BigInt(unwrapClarityValue(json.value));
};

const principalCV = (address: string) => standardPrincipalCV(address);

describe("X-crow core flows", () => {
  beforeEach(() => {
    simnet.mineEmptyBlocks(RATE_LIMIT_BLOCKS + 1);
  });

  it("tracks deposits and approvals state", () => {
    const depositAmount = 500_000n;

    const depositReceipt = mineCall(client, "deposit", [
      principalCV(freelancer),
      uintCV(depositAmount),
    ]);
    unwrapOkJSON(depositReceipt.result);

    const statusAfterDeposit = unwrapOkJSON(
      readOnly("Xcrow-status").result,
    ) as Record<string, any>;
    expect(unwrapClarityValue(statusAfterDeposit.client)).toBe(client);
    expect(unwrapClarityValue(statusAfterDeposit.freelancer)).toBe(
      freelancer,
    );
    expect(BigInt(unwrapClarityValue(statusAfterDeposit.amount))).toBe(
      depositAmount,
    );
    expect(unwrapClarityValue(statusAfterDeposit["deposit-made"])).toBe(true);

    advanceBlocks();
    const duplicateDeposit = mineCall(client, "deposit", [
      principalCV(freelancer),
      uintCV(depositAmount),
    ]);
    expect(unwrapErrCode(duplicateDeposit.result)).toBe(100n);

    advanceBlocks();
    unwrapOkJSON(mineCall(client, "client-approve").result);
    advanceBlocks();
    unwrapOkJSON(mineCall(freelancer, "freelancer-approve").result);

    const statusAfterApprovals = unwrapOkJSON(
      readOnly("Xcrow-status").result,
    ) as Record<string, any>;
    expect(
      unwrapClarityValue(statusAfterApprovals["client-approved"]),
    ).toBe(true);
    expect(
      unwrapClarityValue(statusAfterApprovals["freelancer-approved"]),
    ).toBe(true);

    const feePreview = unwrapOkJSON(
      readOnly("calculate-fee-for-user", [
        principalCV(client),
        uintCV(depositAmount),
      ]).result,
    );
    expect(BigInt(feePreview)).toBeGreaterThan(0n);
  });

  it("enforces the refund timeout window", () => {
    const depositAmount = 300_000n;

    unwrapOkJSON(
      mineCall(client, "deposit", [
        principalCV(freelancer),
        uintCV(depositAmount),
      ]).result,
    );

    advanceBlocks();
    const prematureRefund = mineCall(client, "refund");
    expect(unwrapErrCode(prematureRefund.result)).toBe(106n);

    advanceBlocks(REFUND_TIMEOUT_BLOCKS + RATE_LIMIT_BLOCKS);
    const refundAttempt = mineCall(client, "refund");
    expect(unwrapErrCode(refundAttempt.result)).toBe(4n);
  });

  it("supports milestone delivery tracking and disputes", () => {
    const milestoneAmounts = [200_000n, 300_000n];
    const totalBudget = milestoneAmounts.reduce((acc, amt) => acc + amt, 0n);
    const amountList = listCV(milestoneAmounts.map((amt) => uintCV(amt)));
    const descriptionList = listCV(
      ["Design", "Development"].map((desc) => stringAsciiCV(desc)),
    );
    const futureDeadline = BigInt(simnet.blockHeight + 600);

    const createProject = mineCall(client, "create-milestone-project", [
      principalCV(freelancer),
      uintCV(totalBudget),
      uintCV(futureDeadline),
      amountList,
      descriptionList,
    ]);
    const projectId = BigInt(unwrapOkJSON(createProject.result));
    expect(projectId).toBeGreaterThanOrEqual(1n);

    advanceBlocks();
    const evidenceHash = bufferCV(new Uint8Array(32));
    unwrapOkJSON(
      mineCall(freelancer, "submit-milestone-delivery", [
        uintCV(1n),
        evidenceHash,
      ]).result,
    );

    const escrow = unwrapClarityValue(
      cvToJSON(readOnly("get-milestone-escrow", [uintCV(1n)]).result).value,
    ) as Record<string, any>;
    expect(unwrapClarityValue(escrow["freelancer-delivered"])).toBe(true);
    expect(escrow["evidence-hash"]).toBeDefined();

    advanceBlocks();
    unwrapOkJSON(
      mineCall(client, "set-project-arbiter", [
        uintCV(projectId),
        principalCV(arbiter),
      ]).result,
    );

    advanceBlocks();
    unwrapOkJSON(
      mineCall(freelancer, "raise-milestone-dispute", [uintCV(1n)]).result,
    );

    const projectStatus = unwrapClarityValue(
      cvToJSON(readOnly("get-project-status", [uintCV(projectId)]).result)
        .value,
    ) as Record<string, any>;
    expect(unwrapClarityValue(projectStatus["project-status"])).toBe(
      "disputed",
    );
  });

  it("queues and signs large withdrawals via the multi-sig path", () => {
    const depositAmount = LARGE_WITHDRAW_THRESHOLD;

    unwrapOkJSON(
      mineCall(client, "deposit", [
        principalCV(freelancer),
        uintCV(depositAmount),
      ]).result,
    );

    advanceBlocks();
    unwrapOkJSON(
      mineCall(client, "add-signer", [principalCV(signer)]).result,
    );

    advanceBlocks();
    const proposal = mineCall(client, "propose-large-withdrawal", [
      uintCV(depositAmount),
      principalCV(freelancer),
    ]);
    const txId = BigInt(unwrapOkJSON(proposal.result));
    expect(txId).toBeGreaterThanOrEqual(1n);

    const pending = unwrapClarityValue(
      cvToJSON(
        readOnly("get-pending-transaction", [uintCV(txId)]).result,
      ).value,
    ) as Record<string, any>;
    expect(BigInt(unwrapClarityValue(pending["target-amount"]))).toBe(
      depositAmount,
    );
    expect(unwrapClarityValue(pending["signatures-received"])).toBe("1");

    advanceBlocks();
    unwrapOkJSON(
      mineCall(signer, "sign-pending-transaction", [uintCV(txId)]).result,
    );

    const updatedPending = unwrapClarityValue(
      cvToJSON(
        readOnly("get-pending-transaction", [uintCV(txId)]).result,
      ).value,
    ) as Record<string, any>;
    expect(unwrapClarityValue(updatedPending["signatures-received"])).toBe(
      "2",
    );
    expect(unwrapClarityValue(updatedPending["executed"])).toBe(false);
  });
});
