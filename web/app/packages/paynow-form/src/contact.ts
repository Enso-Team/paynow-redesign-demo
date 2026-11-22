/**
 * A phone number from the address book as an SG mobile, or null.
 * Strips spaces, dashes and brackets, then a leading +65, or 65 when 10 digits remain.
 * Only 8 digits starting with 8 or 9 count, so landlines and foreign numbers give null.
 */
export function contactMobile(phone: string): string | null {
  let digits = phone.replace(/[\s\-()]/g, "");
  if (digits.startsWith("+65")) digits = digits.slice(3);
  else if (digits.startsWith("65") && digits.length === 10) digits = digits.slice(2);
  return /^[89]\d{7}$/.test(digits) ? digits : null;
}
