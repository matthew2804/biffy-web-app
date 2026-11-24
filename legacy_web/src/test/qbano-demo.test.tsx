import { describe, expect, it } from "vitest";
import { act, renderHook } from "@testing-library/react";
import { deliveryPoints, restaurants } from "@/lib/mock-data";
import { isReachable } from "@/lib/format";
import { StoreProvider, useStore } from "@/lib/store";

describe("Qbano Icesi demonstration", () => {
  it("delivers only to Icesi points even if another point is physically nearby", () => {
    const r = restaurants.find((r) => r.id === "qbano-icesi");
    const p = deliveryPoints.find((p) => p.id === "icesi-biblioteca");
    if (!r || !p) throw new Error("Missing Qbano Icesi data");
    expect(isReachable(r, p)).toBe(true);
    expect(isReachable(r, { ...p, id: "outside-campus" })).toBe(false);
  });
  it("starts an Icesi buyer who can schedule a Qbano order", () => {
    const { result } = renderHook(() => useStore(), { wrapper: StoreProvider });
    act(() => result.current.startQbanoDemo());
    expect(result.current.user?.universityId).toBe("icesi");
    expect(result.current.reachableRestaurants.map((r) => r.id)).toEqual(["qbano-icesi"]);
    act(() => result.current.addToCart("qbano-especial"));
    const scheduledFor = "2026-10-16T17:00:00.000Z";
    act(() => { result.current.placeOrder({ scheduledFor, paymentId: "nequi", pointsToUse: 0 }); });
    expect(result.current.orders[0]?.status).toBe("programado");
    expect(result.current.orders[0]?.scheduledFor).toBe(scheduledFor);
    expect(result.current.orders[0]?.pointId).toBe("icesi-biblioteca");
    expect(result.current.orders[0]?.restaurantIds).toEqual(["qbano-icesi"]);
  });
});
describe("Qbano demo details", () => {
  it("delivers in 8 minutes and names the special first", async () => {
    const { restaurants, dishes } = await import("@/lib/mock-data");
    expect(restaurants.find((r) => r.id === "qbano-icesi")?.timeMin).toBe(8);
    expect(dishes.filter((d) => d.restaurantId === "qbano-icesi")[0]?.name).toBe("Qbano Especial");
  });
});
