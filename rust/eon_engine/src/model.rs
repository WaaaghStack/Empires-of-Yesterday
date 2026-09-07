//! Narrow, normalized authority tables + tunable config.
//!
//! This is the *authority* state for the World scope. Per the transaction-engine contract, the
//! hard work happens as ordered transactions over these narrow tables; wide denormalized rows
//! live only in the report/replay layer (`crate::turn::TurnReport`, `crate::battle::BattleReport`).

pub type FactionId = u32;
pub type ProvinceId = u32;
pub type ArmyId = u32;
pub type AgentId = u32;

/// Magic gem paths — the strategic minerals reinterpreted as Dominions-style paths.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[repr(u16)]
pub enum GemPath {
    Aurelium = 0,
    Verdantite = 1,
    Emberstone = 2,
}

impl GemPath {
    pub fn all() -> [GemPath; 3] {
        [GemPath::Aurelium, GemPath::Verdantite, GemPath::Emberstone]
    }
    pub fn as_str(self) -> &'static str {
        match self {
            GemPath::Aurelium => "aurelium",
            GemPath::Verdantite => "verdantite",
            GemPath::Emberstone => "emberstone",
        }
    }
}

/// Campaign unit kinds. MVP art scope is soldiers + bombers only (existing billboards).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnitKind {
    Soldier,
    Bomber,
}

impl UnitKind {
    pub fn as_str(self) -> &'static str {
        match self {
            UnitKind::Soldier => "soldier",
            UnitKind::Bomber => "bomber",
        }
    }
    /// Base per-unit combat stats used to seed battles.
    pub fn base_hp(self) -> f32 {
        match self {
            UnitKind::Soldier => 100.0,
            UnitKind::Bomber => 60.0,
        }
    }
    pub fn base_attack(self) -> f32 {
        match self {
            UnitKind::Soldier => 12.0,
            UnitKind::Bomber => 22.0,
        }
    }
    /// Attack reach in battlefield units (LOS radius).
    pub fn reach(self) -> f32 {
        match self {
            UnitKind::Soldier => 2.0,
            UnitKind::Bomber => 6.0,
        }
    }
    pub fn move_speed(self) -> f32 {
        match self {
            UnitKind::Soldier => 3.0,
            UnitKind::Bomber => 5.0,
        }
    }
}

/// Total-War-style meta agents. The primary player skill lever (battles are hands-off).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentKind {
    Prophet,  // strong mobile dominion amplifier
    Priest,   // weaker mobile dominion amplifier
    Spy,      // sap enemy dominion + raise unrest
    Assassin, // remove enemy agents
    Diplomat, // shift relations
    Scout,    // reveal / find deposits (sets flags)
}

impl AgentKind {
    pub fn as_str(self) -> &'static str {
        match self {
            AgentKind::Prophet => "prophet",
            AgentKind::Priest => "priest",
            AgentKind::Spy => "spy",
            AgentKind::Assassin => "assassin",
            AgentKind::Diplomat => "diplomat",
            AgentKind::Scout => "scout",
        }
    }
}

#[derive(Clone, Debug)]
pub struct Faction {
    pub id: FactionId,
    pub name: String,
    pub is_ai: bool,
    pub alive: bool,
    pub ascension_points: u32,
}

/// A regiment carried by an army on the campaign map; expands into individual units in battle.
#[derive(Clone, Debug)]
pub struct Squad {
    pub kind: UnitKind,
    pub count: u32,
}

#[derive(Clone, Debug)]
pub struct Army {
    pub id: ArmyId,
    pub faction: FactionId,
    pub province: ProvinceId,
    pub squads: Vec<Squad>,
    /// Movement order for the turn (set by orders/AI); resolved in the Movement phase.
    pub move_to: Option<ProvinceId>,
}

impl Army {
    pub fn total_units(&self) -> u32 {
        self.squads.iter().map(|s| s.count).sum()
    }
    pub fn is_empty(&self) -> bool {
        self.total_units() == 0
    }
}

#[derive(Clone, Debug)]
pub struct Agent {
    pub id: AgentId,
    pub faction: FactionId,
    pub province: ProvinceId,
    pub kind: AgentKind,
    pub level: u8,
    pub alive: bool,
    /// Optional per-turn action target province (spy/assassin/diplomat/scout).
    pub target: Option<ProvinceId>,
    pub move_to: Option<ProvinceId>,
}

#[derive(Clone, Debug)]
pub struct Province {
    pub id: ProvinceId,
    pub name: String,
    pub is_land: bool,
    /// Terrain elevation 0..100. **Ignored by dominion diffusion** (height-independent tide);
    /// still meaningful for battle terrain / movement (see design lock change).
    pub elevation: u8,
    pub neighbors: Vec<ProvinceId>,
    /// Per-faction dominion mass (length == faction count). The visible "faith tide".
    pub dom: Vec<f32>,
    pub unrest: f32,
    /// A built temple acts as a fixed dominion amplifier for its owner.
    pub temple_owner: Option<FactionId>,
    /// Faction whose capital sits here (strongest fixed source).
    pub capital_of: Option<FactionId>,
    pub has_throne: bool,
    pub deposit: Option<GemPath>,
    pub revealed: bool,
}

impl Province {
    /// Current owner by dominion majority, or None if neutral/contested-below-threshold.
    pub fn owner(&self, cfg: &Config) -> Option<FactionId> {
        if !self.is_land {
            return None;
        }
        let mut best: Option<(FactionId, f32)> = None;
        let mut second = 0.0f32;
        for (fid, &d) in self.dom.iter().enumerate() {
            match best {
                Some((_, bd)) if d > bd => {
                    second = bd;
                    best = Some((fid as FactionId, d));
                }
                Some((_, _)) => {
                    if d > second {
                        second = d;
                    }
                }
                None => best = Some((fid as FactionId, d)),
            }
        }
        match best {
            Some((fid, bd)) if bd >= cfg.owner_min_dominion && bd > second + 1e-4 => Some(fid),
            _ => None,
        }
    }
}

/// Tunable engine constants. Slow dominion + turn cadence is the "creep" identity.
#[derive(Clone, Debug)]
pub struct Config {
    pub dominion_spread_rate: f32,
    pub cancel_rate: f32,
    pub owner_min_dominion: f32,
    pub capital_output: f32,
    pub temple_output: f32,
    pub prophet_output: f32,
    pub priest_output: f32,
    pub spy_sap: f32,
    pub spy_unrest: f32,
    pub assassin_base_chance: f32,
    pub unrest_from_enemy: f32,
    pub unrest_decay: f32,
    pub unrest_threshold: f32,
    pub unrest_faith_erosion: f32,
    pub gem_per_deposit: f32,
    pub thrones_to_win: u32,
    pub dominion_alive_eps: f32,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            dominion_spread_rate: 0.06, // slow tide
            cancel_rate: 0.35,
            owner_min_dominion: 1.0,
            capital_output: 6.0,
            temple_output: 3.0,
            prophet_output: 5.0,
            priest_output: 3.0,
            spy_sap: 4.0,
            spy_unrest: 3.0,
            assassin_base_chance: 0.5,
            unrest_from_enemy: 0.02,
            unrest_decay: 0.1,
            unrest_threshold: 5.0,
            unrest_faith_erosion: 0.5,
            gem_per_deposit: 2.0,
            thrones_to_win: 2,
            dominion_alive_eps: 0.5,
        }
    }
}

/// The World authority state.
#[derive(Clone, Debug)]
pub struct World {
    pub seed: u64,
    pub turn: u32,
    pub cfg: Config,
    pub factions: Vec<Faction>,
    pub provinces: Vec<Province>,
    pub armies: Vec<Army>,
    pub agents: Vec<Agent>,
    /// Relations matrix [a][b] in [-100, 100]; symmetric by convention.
    pub relations: Vec<Vec<i16>>,
    pub next_army_id: ArmyId,
    pub next_agent_id: AgentId,
}

impl World {
    pub fn faction_count(&self) -> usize {
        self.factions.len()
    }

    pub fn province(&self, id: ProvinceId) -> &Province {
        &self.provinces[id as usize]
    }

    /// Sum of a faction's dominion across all provinces (the ledger reconciliation target).
    pub fn total_dominion(&self, f: FactionId) -> f32 {
        self.provinces.iter().map(|p| p.dom[f as usize]).sum()
    }

    /// Count of land provinces a faction owns.
    pub fn owned_land(&self, f: FactionId) -> usize {
        self.provinces
            .iter()
            .filter(|p| p.owner(&self.cfg) == Some(f))
            .count()
    }

    pub fn land_count(&self) -> usize {
        self.provinces.iter().filter(|p| p.is_land).count()
    }

    /// Owned thrones for a faction.
    pub fn owned_thrones(&self, f: FactionId) -> u32 {
        self.provinces
            .iter()
            .filter(|p| p.has_throne && p.owner(&self.cfg) == Some(f))
            .count() as u32
    }

    /// Deterministic world-state digest (proves turn replay determinism).
    pub fn digest(&self) -> u64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut mix = |x: u64| {
            h ^= x;
            h = h.wrapping_mul(0x0000_0100_0000_01B3);
        };
        mix(self.turn as u64);
        for p in &self.provinces {
            mix(p.id as u64);
            mix((p.unrest * 1000.0).round() as i64 as u64);
            for d in &p.dom {
                mix((*d * 1000.0).round() as i64 as u64);
            }
            mix(p.owner(&self.cfg).map(|f| f as u64 + 1).unwrap_or(0));
        }
        for a in &self.armies {
            mix(a.id as u64);
            mix(a.faction as u64);
            mix(a.province as u64);
            mix(a.total_units() as u64);
        }
        for ag in &self.agents {
            mix(ag.id as u64);
            mix(ag.alive as u64);
            mix(ag.province as u64);
        }
        for f in &self.factions {
            mix(f.alive as u64);
            mix(f.ascension_points as u64);
        }
        h
    }
}
