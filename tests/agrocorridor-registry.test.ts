// AgroCorridorRegistry.test.ts
import { describe, expect, it, vi, beforeEach } from "vitest";

// Interfaces for type safety
interface ClarityResponse<T> {
  ok: boolean;
  value: T | number; // number for error codes
}

interface Corridor {
  boundaries: string;
  species: string;
  regions: string[]; // principals as strings for mock
  owner: string;
  createdAt: number;
  updatedAt: number;
  description: string;
  active: boolean;
}

interface Stakeholder {
  role: string;
  permissions: string[];
  addedAt: number;
}

interface Version {
  changes: string;
  timestamp: number;
  updater: string;
}

interface Status {
  status: string;
  visibility: boolean;
  lastChecked: number;
}

interface Metrics {
  biodiversityScore: number;
  carbonSequestered: number;
  areaCovered: number;
}

interface Tags {
  tags: string[];
}

interface ContractState {
  admin: string;
  paused: boolean;
  corridorCounter: number;
  corridors: Map<number, Corridor>;
  stakeholders: Map<string, Stakeholder>; // key: `${id}-${stakeholder}`
  versions: Map<string, Version>; // key: `${id}-${version}`
  statuses: Map<number, Status>;
  metrics: Map<number, Metrics>;
  tags: Map<number, Tags>;
  versionCounts: Map<number, number>;
}

// Mock contract implementation
class AgroCorridorRegistryMock {
  private state: ContractState = {
    admin: "deployer",
    paused: false,
    corridorCounter: 0,
    corridors: new Map(),
    stakeholders: new Map(),
    versions: new Map(),
    statuses: new Map(),
    metrics: new Map(),
    tags: new Map(),
    versionCounts: new Map(),
  };

  private MAX_BOUNDARY_LEN = 512;
  private MAX_SPECIES_LEN = 256;
  private MAX_DESCRIPTION_LEN = 1024;
  private MAX_STAKEHOLDERS = 20;
  private MAX_TAGS = 15;
  private ERR_UNAUTHORIZED = 100;
  private ERR_ALREADY_REGISTERED = 101;
  private ERR_NOT_FOUND = 102;
  private ERR_INVALID_PARAM = 103;
  private ERR_PAUSED = 104;
  private ERR_MAX_STAKEHOLDERS = 106;

  private getCurrentHeight(): number {
    return Date.now(); // Mock block height
  }

  pauseContract(caller: string): ClarityResponse<boolean> {
    if (caller !== this.state.admin) {
      return { ok: false, value: this.ERR_UNAUTHORIZED };
    }
    this.state.paused = true;
    return { ok: true, value: true };
  }

  unpauseContract(caller: string): ClarityResponse<boolean> {
    if (caller !== this.state.admin) {
      return { ok: false, value: this.ERR_UNAUTHORIZED };
    }
    this.state.paused = false;
    return { ok: true, value: true };
  }

  setAdmin(caller: string, newAdmin: string): ClarityResponse<boolean> {
    if (caller !== this.state.admin) {
      return { ok: false, value: this.ERR_UNAUTHORIZED };
    }
    this.state.admin = newAdmin;
    return { ok: true, value: true };
  }

  registerCorridor(
    caller: string,
    boundaries: string,
    species: string,
    regions: string[],
    description: string
  ): ClarityResponse<number> {
    if (this.state.paused) {
      return { ok: false, value: this.ERR_PAUSED };
    }
    if (boundaries.length === 0 || species.length === 0 || regions.length === 0) {
      return { ok: false, value: this.ERR_INVALID_PARAM };
    }
    if (boundaries.length > this.MAX_BOUNDARY_LEN || species.length > this.MAX_SPECIES_LEN || description.length > this.MAX_DESCRIPTION_LEN) {
      return { ok: false, value: this.ERR_INVALID_PARAM };
    }
    const id = this.state.corridorCounter + 1;
    const height = this.getCurrentHeight();
    this.state.corridors.set(id, {
      boundaries,
      species,
      regions,
      owner: caller,
      createdAt: height,
      updatedAt: height,
      description,
      active: true,
    });
    this.state.statuses.set(id, {
      status: "planning",
      visibility: true,
      lastChecked: height,
    });
    this.state.metrics.set(id, {
      biodiversityScore: 0,
      carbonSequestered: 0,
      areaCovered: 0,
    });
    this.state.corridorCounter = id;
    return { ok: true, value: id };
  }

  updateCorridor(
    caller: string,
    id: number,
    newBoundaries?: string,
    newSpecies?: string,
    newDescription?: string
  ): ClarityResponse<boolean> {
    if (this.state.paused) {
      return { ok: false, value: this.ERR_PAUSED };
    }
    const corridor = this.state.corridors.get(id);
    if (!corridor) {
      return { ok: false, value: this.ERR_NOT_FOUND };
    }
    if (corridor.owner !== caller) {
      return { ok: false, value: this.ERR_UNAUTHORIZED };
    }
    const height = this.getCurrentHeight();
    const updatedCorridor = {
      ...corridor,
      boundaries: newBoundaries ?? corridor.boundaries,
      species: newSpecies ?? corridor.species,
      description: newDescription ?? corridor.description,
      updatedAt: height,
    };
    this.state.corridors.set(id, updatedCorridor);
    const versionCount = this.state.versionCounts.get(id) ?? 0;
    this.state.versions.set(`${id}-${versionCount + 1}`, {
      changes: "Updated boundaries, species, or description",
      timestamp: height,
      updater: caller,
    });
    this.state.versionCounts.set(id, versionCount + 1);
    return { ok: true, value: true };
  }

  addStakeholder(
    caller: string,
    id: number,
    stakeholder: string,
    role: string,
    permissions: string[]
  ): ClarityResponse<boolean> {
    if (this.state.paused) {
      return { ok: false, value: this.ERR_PAUSED };
    }
    const corridor = this.state.corridors.get(id);
    if (!corridor) {
      return { ok: false, value: this.ERR_NOT_FOUND };
    }
    if (corridor.owner !== caller) {
      return { ok: false, value: this.ERR_UNAUTHORIZED };
    }
    const key = `${id}-${stakeholder}`;
    if (this.state.stakeholders.has(key)) {
      return { ok: false, value: this.ERR_ALREADY_REGISTERED };
    }
    // Mock stakeholder count
    let count = 0;
    this.state.stakeholders.forEach((_, k) => {
      if (k.startsWith(`${id}-`)) count++;
    });
    if (count >= this.MAX_STAKEHOLDERS) {
      return { ok: false, value: this.ERR_MAX_STAKEHOLDERS };
    }
    this.state.stakeholders.set(key, {
      role,
      permissions,
      addedAt: this.getCurrentHeight(),
    });
    return { ok: true, value: true };
  }

  removeStakeholder(caller: string, id: number, stakeholder: string): ClarityResponse<boolean> {
    if (this.state.paused) {
      return { ok: false, value: this.ERR_PAUSED };
    }
    const corridor = this.state.corridors.get(id);
    if (!corridor) {
      return { ok: false, value: this.ERR_NOT_FOUND };
    }
    if (corridor.owner !== caller) {
      return { ok: false, value: this.ERR_UNAUTHORIZED };
    }
    const key = `${id}-${stakeholder}`;
    if (!this.state.stakeholders.has(key)) {
      return { ok: false, value: this.ERR_NOT_FOUND };
    }
    this.state.stakeholders.delete(key);
    return { ok: true, value: true };
  }

  // Additional methods for other functions would follow similar patterns...

  getCorridorDetails(id: number): ClarityResponse<Corridor | null> {
    return { ok: true, value: this.state.corridors.get(id) ?? null };
  }

  isPaused(): ClarityResponse<boolean> {
    return { ok: true, value: this.state.paused };
  }

  getAdmin(): ClarityResponse<string> {
    return { ok: true, value: this.state.admin };
  }

  getTotalCorridors(): ClarityResponse<number> {
    return { ok: true, value: this.state.corridorCounter };
  }
}

// Test setup
const accounts = {
  deployer: "deployer",
  user1: "wallet_1",
  user2: "wallet_2",
};

describe("AgroCorridorRegistry Contract", () => {
  let contract: AgroCorridorRegistryMock;

  beforeEach(() => {
    contract = new AgroCorridorRegistryMock();
    vi.resetAllMocks();
  });

  it("should initialize with correct defaults", () => {
    expect(contract.getAdmin()).toEqual({ ok: true, value: "deployer" });
    expect(contract.isPaused()).toEqual({ ok: true, value: false });
    expect(contract.getTotalCorridors()).toEqual({ ok: true, value: 0 });
  });

  it("should allow admin to pause and unpause", () => {
    let result = contract.pauseContract(accounts.deployer);
    expect(result).toEqual({ ok: true, value: true });
    expect(contract.isPaused()).toEqual({ ok: true, value: true });

    result = contract.unpauseContract(accounts.deployer);
    expect(result).toEqual({ ok: true, value: true });
    expect(contract.isPaused()).toEqual({ ok: true, value: false });
  });

  it("should prevent non-admin from pausing", () => {
    const result = contract.pauseContract(accounts.user1);
    expect(result).toEqual({ ok: false, value: 100 });
  });

  it("should register a new corridor", () => {
    const result = contract.registerCorridor(
      accounts.user1,
      "GeoJSON boundaries",
      "Trees and crops",
      [accounts.user2],
      "Detailed plan"
    );
    expect(result.ok).toBe(true);
    const id = result.value as number;
    expect(id).toBe(1);

    const details = contract.getCorridorDetails(id);
    expect(details).toEqual({
      ok: true,
      value: expect.objectContaining({
        owner: accounts.user1,
        active: true,
      }),
    });
  });

  it("should prevent registration when paused", () => {
    contract.pauseContract(accounts.deployer);
    const result = contract.registerCorridor(
      accounts.user1,
      "GeoJSON",
      "Species",
      [accounts.user2],
      "Desc"
    );
    expect(result).toEqual({ ok: false, value: 104 });
  });

  it("should update corridor details", () => {
    contract.registerCorridor(
      accounts.user1,
      "Old boundaries",
      "Old species",
      [accounts.user2],
      "Old desc"
    );
    const updateResult = contract.updateCorridor(
      accounts.user1,
      1,
      "New boundaries",
      undefined,
      "New desc"
    );
    expect(updateResult).toEqual({ ok: true, value: true });

    const details = contract.getCorridorDetails(1);
    expect(details.value).toEqual(expect.objectContaining({
      boundaries: "New boundaries",
      description: "New desc",
      species: "Old species",
    }));
  });

  it("should prevent update by non-owner", () => {
    contract.registerCorridor(
      accounts.user1,
      "Boundaries",
      "Species",
      [accounts.user2],
      "Desc"
    );
    const updateResult = contract.updateCorridor(
      accounts.user2,
      1,
      "New"
    );
    expect(updateResult).toEqual({ ok: false, value: 100 });
  });

  it("should add and remove stakeholder", () => {
    contract.registerCorridor(
      accounts.user1,
      "Boundaries",
      "Species",
      [accounts.user2],
      "Desc"
    );
    const addResult = contract.addStakeholder(
      accounts.user1,
      1,
      accounts.user2,
      "farmer",
      ["update"]
    );
    expect(addResult).toEqual({ ok: true, value: true });

    const removeResult = contract.removeStakeholder(accounts.user1, 1, accounts.user2);
    expect(removeResult).toEqual({ ok: true, value: true });
  });
});