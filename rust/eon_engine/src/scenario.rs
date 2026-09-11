//! World builders + balanced roster seeding, shared by tests and the headless demo.

use crate::ledger::{Account, Ledger, Phase};
use crate::model::{
    Agent, AgentKind, Army, ArmyId, Config, Faction, FactionId, GemPath, Province, ProvinceId,
    Squad, UnitKind, World,
};
use crate::rng::Rng;

/// Empty two-faction world with an `n`-province land chain; capitals at the ends. No armies yet.
pub fn duel_line(n: usize, seed: u64) -> (World, Ledger) {
    assert!(n >= 2);
    let factions = vec![
        Faction { id: 0, name: "Azure".into(), is_ai: false, alive: true, ascension_points: 0 },
        Faction { id: 1, name: "Crimson".into(), is_ai: true, alive: true, ascension_points: 0 },
    ];
    let mut provinces = Vec::with_capacity(n);
    for i in 0..n {
        let mut neighbors = Vec::new();
        if i > 0 {
            neighbors.push((i - 1) as ProvinceId);
        }
        if i + 1 < n {
            neighbors.push((i + 1) as ProvinceId);
        }
        provinces.push(Province {
            id: i as ProvinceId,
            name: format!("P{i}"),
            is_land: true,
            elevation: 30,
            neighbors,
            dom: vec![0.0; 2],
            unrest: 0.0,
            temple_owner: None,
            capital_of: None,
            has_throne: false,
            deposit: None,
            revealed: false,
        });
    }
    provinces[0].capital_of = Some(0);
    provinces[n - 1].capital_of = Some(1);

    let world = World {
        seed,
        turn: 0,
        cfg: Config::default(),
        factions,
        provinces,
        armies: Vec::new(),
        agents: Vec::new(),
        relations: vec![vec![0; 2]; 2],
        next_army_id: 0,
        next_agent_id: 0,
    };
    (world, Ledger::new())
}

/// Recruit an army (balanced: UnitsAlive credited from UnitSource).
pub fn recruit_army(
    world: &mut World,
    ledger: &mut Ledger,
    faction: FactionId,
    province: ProvinceId,
    squads: Vec<Squad>,
) -> ArmyId {
    let total: u32 = squads.iter().map(|s| s.count).sum();
    let id = world.next_army_id;
    world.next_army_id += 1;
    world.armies.push(Army { id, faction, province, squads, move_to: None });
    if total > 0 {
        ledger.post(
            world.turn,
            Phase::Income,
            "recruit",
            vec![
                (Account::UnitsAlive(faction), total as f64),
                (Account::UnitSource(faction), -(total as f64)),
            ],
            format!("recruit f{faction} @prov{province} x{total}"),
        );
    }
    id
}

/// Seed starting faith into a province *through the ledger* so the books reconcile from turn 0.
pub fn seed_dominion(
    world: &mut World,
    ledger: &mut Ledger,
    province: ProvinceId,
    faction: FactionId,
    amount: f32,
) {
    world.provinces[province as usize].dom[faction as usize] += amount;
    ledger.post(
        world.turn,
        Phase::Income,
        "seed_dominion",
        vec![
            (Account::Dominion(faction), amount as f64),
            (Account::DominionSource(faction), -(amount as f64)),
        ],
        format!("seed f{faction} @prov{province}"),
    );
}

pub fn add_agent(
    world: &mut World,
    faction: FactionId,
    province: ProvinceId,
    kind: AgentKind,
    level: u8,
) {
    let id = world.next_agent_id;
    world.next_agent_id += 1;
    world.agents.push(Agent {
        id,
        faction,
        province,
        kind,
        level,
        alive: true,
        target: None,
        move_to: None,
    });
}

/// A small, feature-complete demo world for the headless self-check: two capitals on a ring,
/// thrones, gem deposits, starting armies, a prophet and a spy per side.
pub fn demo_world(seed: u64) -> (World, Ledger) {
    let n = 8usize; // ring of 8 provinces
    let (mut world, mut ledger) = duel_line(n, seed);
    // Close the chain into a ring so the tide can flow both ways.
    world.provinces[0].neighbors.push((n - 1) as ProvinceId);
    world.provinces[n - 1].neighbors.push(0);
    for p in world.provinces.iter_mut() {
        p.neighbors.sort_unstable();
        p.neighbors.dedup();
    }
    // Thrones opposite the capitals; deposits scattered.
    world.provinces[2].has_throne = true;
    world.provinces[6].has_throne = true;
    world.provinces[1].deposit = Some(GemPath::Aurelium);
    world.provinces[3].deposit = Some(GemPath::Verdantite);
    world.provinces[5].deposit = Some(GemPath::Emberstone);
    world.provinces[7].deposit = Some(GemPath::Aurelium);

    // Starting faith so capitals own their home tile immediately (posted → reconciles).
    seed_dominion(&mut world, &mut ledger, 0, 0, 10.0);
    seed_dominion(&mut world, &mut ledger, (n - 1) as ProvinceId, 1, 10.0);

    // Starting armies at the capitals.
    recruit_army(&mut world, &mut ledger, 0, 0, vec![
        Squad { kind: crate::model::UnitKind::Soldier, count: 40 },
        Squad { kind: crate::model::UnitKind::Bomber, count: 10 },
    ]);
    recruit_army(&mut world, &mut ledger, 1, (n - 1) as ProvinceId, vec![
        Squad { kind: crate::model::UnitKind::Soldier, count: 40 },
        Squad { kind: crate::model::UnitKind::Bomber, count: 10 },
    ]);

    // A prophet and a spy per side.
    add_agent(&mut world, 0, 0, AgentKind::Prophet, 2);
    add_agent(&mut world, 0, 0, AgentKind::Spy, 1);
    add_agent(&mut world, 1, (n - 1) as ProvinceId, AgentKind::Prophet, 2);
    add_agent(&mut world, 1, (n - 1) as ProvinceId, AgentKind::Spy, 1);

    (world, ledger)
}

/// Build a World from an externally-supplied province partition (e.g. large provinces carved from
/// the 3D Earth tiles by the Godot presentation). All provinces are land; the caller supplies
/// adjacency, capital/throne/deposit assignments. Capitals are seeded with starting faith and one
/// starting army each (soldiers + a few bombers). Two factions.
pub fn from_partition(
    seed: u64,
    faction_count: usize,
    neighbors: Vec<Vec<u32>>,
    capital_of: Vec<i32>,
    has_throne: Vec<bool>,
    deposit: Vec<i32>,
    army_soldiers: u32,
    army_bombers: u32,
) -> (World, Ledger) {
    let n = neighbors.len();
    let fc = faction_count.max(2);
    let names = ["Azure", "Crimson", "Verdant", "Golden"];
    let mut factions = Vec::with_capacity(fc);
    for i in 0..fc {
        factions.push(Faction {
            id: i as FactionId,
            name: names.get(i).copied().unwrap_or("Faction").to_string(),
            is_ai: i != 0,
            alive: true,
            ascension_points: 0,
        });
    }
    let mut provinces = Vec::with_capacity(n);
    for i in 0..n {
        let dep = deposit.get(i).copied().unwrap_or(-1);
        let dep_path = match dep {
            0 => Some(GemPath::Aurelium),
            1 => Some(GemPath::Verdantite),
            2 => Some(GemPath::Emberstone),
            _ => None,
        };
        provinces.push(Province {
            id: i as ProvinceId,
            name: format!("P{i}"),
            is_land: true,
            elevation: 30,
            neighbors: neighbors[i].clone(),
            dom: vec![0.0; fc],
            unrest: 0.0,
            temple_owner: None,
            capital_of: capital_of.get(i).and_then(|&c| if c >= 0 { Some(c as FactionId) } else { None }),
            has_throne: has_throne.get(i).copied().unwrap_or(false),
            deposit: dep_path,
            revealed: false,
        });
    }
    // On a large connected map, instant ascension ends things before armies clash. Keep thrones as
    // map flavor but make ascension effectively unreachable so the campaign plays out and is
    // decided by the turn-limit score victory (with battles happening along the contested frontier).
    let mut cfg = Config::default();
    cfg.thrones_to_win = 9999;
    cfg.turn_limit = 15;
    let mut world = World {
        seed,
        turn: 0,
        cfg,
        factions,
        provinces,
        armies: Vec::new(),
        agents: Vec::new(),
        relations: vec![vec![0; fc]; fc],
        next_army_id: 0,
        next_agent_id: 0,
    };
    let mut ledger = Ledger::new();
    // Seed capitals: starting faith + a starting army + a prophet amplifier.
    let caps: Vec<(usize, FactionId)> = (0..n)
        .filter_map(|i| world.provinces[i].capital_of.map(|f| (i, f)))
        .collect();
    for (pid, f) in caps {
        seed_dominion(&mut world, &mut ledger, pid as ProvinceId, f, 12.0);
        let mut squads = Vec::new();
        if army_soldiers > 0 {
            squads.push(Squad { kind: UnitKind::Soldier, count: army_soldiers });
        }
        if army_bombers > 0 {
            squads.push(Squad { kind: UnitKind::Bomber, count: army_bombers });
        }
        if !squads.is_empty() {
            recruit_army(&mut world, &mut ledger, f, pid as ProvinceId, squads);
        }
        add_agent(&mut world, f, pid as ProvinceId, AgentKind::Prophet, 2);
    }
    (world, ledger)
}

/// A seed-varied two-faction ring world for AI-vs-AI validation: capitals sit opposite each other,
/// while starting army sizes, throne placement, and deposits are randomized by seed so different
/// seeds produce genuinely different (but deterministic) campaigns.
pub fn procedural_world(seed: u64) -> (World, Ledger) {
    let n = 10usize;
    let (mut world, mut ledger) = duel_line(n, seed);
    // Close into a ring.
    world.provinces[0].neighbors.push((n - 1) as ProvinceId);
    world.provinces[n - 1].neighbors.push(0);
    for p in world.provinces.iter_mut() {
        p.neighbors.sort_unstable();
        p.neighbors.dedup();
    }
    // Capitals opposite each other.
    let cap_a = 0usize;
    let cap_b = n / 2;
    for p in world.provinces.iter_mut() {
        p.capital_of = None;
    }
    world.provinces[cap_a].capital_of = Some(0);
    world.provinces[cap_b].capital_of = Some(1);

    let mut rng = Rng::new(seed ^ 0xA1B2_C3D4);

    // Thrones: two distinct non-capital provinces.
    let mut placed = 0;
    let mut guard = 0;
    while placed < 2 && guard < 100 {
        guard += 1;
        let p = rng.below(n as u32) as usize;
        if p != cap_a && p != cap_b && !world.provinces[p].has_throne {
            world.provinces[p].has_throne = true;
            placed += 1;
        }
    }
    // Deposits: ~4 provinces get a random gem path.
    for _ in 0..4 {
        let p = rng.below(n as u32) as usize;
        let path = GemPath::all()[rng.below(3) as usize];
        world.provinces[p].deposit = Some(path);
    }

    // Starting faith at capitals (posted → reconciles).
    seed_dominion(&mut world, &mut ledger, cap_a as ProvinceId, 0, 10.0);
    seed_dominion(&mut world, &mut ledger, cap_b as ProvinceId, 1, 10.0);

    // Seed-varied starting armies (asymmetric → varied battle outcomes).
    let sol_a = 30 + rng.below(30);
    let bom_a = 5 + rng.below(10);
    let sol_b = 30 + rng.below(30);
    let bom_b = 5 + rng.below(10);
    recruit_army(&mut world, &mut ledger, 0, cap_a as ProvinceId, vec![
        Squad { kind: UnitKind::Soldier, count: sol_a },
        Squad { kind: UnitKind::Bomber, count: bom_a },
    ]);
    recruit_army(&mut world, &mut ledger, 1, cap_b as ProvinceId, vec![
        Squad { kind: UnitKind::Soldier, count: sol_b },
        Squad { kind: UnitKind::Bomber, count: bom_b },
    ]);

    // A prophet + spy per side at their capitals.
    add_agent(&mut world, 0, cap_a as ProvinceId, AgentKind::Prophet, 2);
    add_agent(&mut world, 0, cap_a as ProvinceId, AgentKind::Spy, 1);
    add_agent(&mut world, 1, cap_b as ProvinceId, AgentKind::Prophet, 2);
    add_agent(&mut world, 1, cap_b as ProvinceId, AgentKind::Spy, 1);

    (world, ledger)
}
