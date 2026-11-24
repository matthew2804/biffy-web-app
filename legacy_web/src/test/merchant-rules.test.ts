import { describe, expect, it } from "vitest";
import { emptyProduct, incBreakdown, productErrors } from "@/lib/merchant";
import { demoProducts } from "@/lib/merchant-demo";

describe("merchant product rules", () => {
  it("a complete product is publishable", () => {
    expect(productErrors(demoProducts[0]!, true)).toEqual([]);
  });
  it("cannot publish without a photo", () => {
    expect(productErrors({ ...demoProducts[0]!, photo: "" }, false)).toContain("Sube la foto principal del plato");
  });
  it("cannot publish without at least one sede", () => {
    expect(productErrors({ ...demoProducts[0]!, sedeIds: [] }, false)).toContain("Selecciona al menos una sede");
  });
  it("nutrition is required only when the restaurant shows it", () => {
    const p = { ...demoProducts[0]!, nutrition: null };
    expect(productErrors(p, false)).toEqual([]);
    expect(productErrors(p, true).length).toBe(1);
  });
  it("an empty product lists every missing field", () => {
    expect(productErrors(emptyProduct("x", []), false).length).toBeGreaterThanOrEqual(7);
  });
  it("INC 8% is included in the price for responsible restaurants", () => {
    expect(incBreakdown(10800, true)).toEqual({ base: 10000, inc: 800 });
    expect(incBreakdown(10800, false)).toEqual({ base: 10800, inc: 0 });
  });
});
