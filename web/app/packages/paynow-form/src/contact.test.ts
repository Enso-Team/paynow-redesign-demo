import { describe, expect, it } from "vitest";
import { contactMobile } from "./contact";

describe("contactMobile", () => {
  it.each([
    ["+65 9123 4567", "91234567"],
    ["6591234567", "91234567"],
    ["9123-4567", "91234567"],
    ["(+65) 91234567", "91234567"],
    ["8765 4321", "87654321"],
  ])("reads %s as an SG mobile", (phone, mobile) => {
    expect(contactMobile(phone)).toBe(mobile);
  });

  it.each([
    ["+44 7700 900123"],
    ["+60 12-345 6789"],
    ["6123 4567"],
    ["+65 6123 4567"],
    ["912345"],
  ])("rejects %s", (phone) => {
    expect(contactMobile(phone)).toBeNull();
  });
});
