struct EngineProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let idleRPM: Double
    let redlineRPM: Double
    let softLimiterRPM: Double
    let hardLimiterRPM: Double
    let audioFolder: String
    let cylinders: Int
    let hasTurbo: Bool
    let rotaryRotors: Int
    let audioReferences: [Double]?
    let soundDescription: String?
    var firingEventsPerRevolution: Double { rotaryRotors > 0 ? Double(rotaryRotors) : Double(cylinders) / 2 }
    init(id: String, name: String, idleRPM: Double, redlineRPM: Double,
         softLimiterRPM: Double, hardLimiterRPM: Double, audioFolder: String,
         cylinders: Int, hasTurbo: Bool, rotaryRotors: Int = 0,
         audioReferences: [Double]? = nil, soundDescription: String? = nil) {
        self.id = id; self.name = name; self.idleRPM = idleRPM; self.redlineRPM = redlineRPM
        self.softLimiterRPM = softLimiterRPM; self.hardLimiterRPM = hardLimiterRPM
        self.audioFolder = audioFolder; self.cylinders = cylinders; self.hasTurbo = hasTurbo
        self.rotaryRotors = rotaryRotors; self.audioReferences = audioReferences
        self.soundDescription = soundDescription
    }
    var maximumRPM: Double { redlineRPM }
    var redlineScale: Double { redlineRPM / 6500 }

    static let americanV8 = EngineProfile(
        id: "american-62", name: "American 6.2L NA V8", idleRPM: 750, redlineRPM: 6500,
        softLimiterRPM: 6400, hardLimiterRPM: 6700, audioFolder: "V8_62_NA", cylinders: 8, hasTurbo: false
    )
    static let bmwS65 = EngineProfile(
        id: "bmw-s65", name: "BMW M3 E90/E92/E93 · 4.0L S65 V8", idleRPM: 800,
        redlineRPM: 8400, softLimiterRPM: 8300, hardLimiterRPM: 8500,
        audioFolder: "BMW_S65", cylinders: 8, hasTurbo: false
    )
    static let supra2JZ = EngineProfile(
        id: "supra-2jz", name: "Toyota Supra Mk4 · 3.0L 2JZ-GTE Twin Turbo", idleRPM: 750,
        redlineRPM: 6800, softLimiterRPM: 6700, hardLimiterRPM: 7000,
        audioFolder: "Supra_2JZ", cylinders: 6, hasTurbo: true
    )
    static let amgGTR = EngineProfile(
        id: "amg-gtr", name: "Mercedes-AMG GT R · 4.0L Biturbo V8", idleRPM: 750,
        redlineRPM: 7000, softLimiterRPM: 6900, hardLimiterRPM: 7200,
        audioFolder: "AMG_GTR", cylinders: 8, hasTurbo: true
    )
    static let lexusLFA = EngineProfile(
        id: "lexus-lfa", name: "Lexus LFA · 4.8L V10", idleRPM: 900, redlineRPM: 9000,
        softLimiterRPM: 8900, hardLimiterRPM: 9200, audioFolder: "Lexus_LFA", cylinders: 10, hasTurbo: false,
        audioReferences: [900, 1800, 3400, 4800, 6200, 7600, 8800],
        soundDescription: "LFA-inspired recreation · Bright V10 and induction harmonics"
    )
    static let murcielago = EngineProfile(
        id: "lamborghini-murcielago", name: "Lamborghini Murciélago · 6.2L V12", idleRPM: 900, redlineRPM: 7600,
        softLimiterRPM: 7500, hardLimiterRPM: 7800, audioFolder: "Lamborghini_Murcielago", cylinders: 12, hasTurbo: false,
        audioReferences: [900, 1600, 2900, 4100, 5300, 6400, 7400],
        soundDescription: "Murciélago-inspired recreation · Layered V12 howl"
    )
    static let porsche996GT3 = EngineProfile(
        id: "porsche-996-gt3", name: "Porsche 911 GT3 (996) · 3.6L Flat-Six", idleRPM: 850, redlineRPM: 7800,
        softLimiterRPM: 7700, hardLimiterRPM: 8000, audioFolder: "Porsche_996_GT3", cylinders: 6, hasTurbo: false,
        audioReferences: [850, 1700, 3000, 4200, 5500, 6600, 7600],
        soundDescription: "996 GT3-inspired recreation · Mechanical flat-six rasp"
    )
    static let mazdaRX7 = EngineProfile(
        id: "mazda-rx7-fd", name: "Mazda RX-7 FD · 13B-REW Twin-Turbo Rotary", idleRPM: 850, redlineRPM: 8000,
        softLimiterRPM: 7900, hardLimiterRPM: 8200, audioFolder: "Mazda_RX7_FD", cylinders: 0, hasTurbo: true,
        rotaryRotors: 2, audioReferences: [850, 1800, 3100, 4400, 5600, 6800, 7800],
        soundDescription: "RX-7-inspired recreation · Rotary buzz, turbo intake and release"
    )
    static let ferrariF355 = EngineProfile(
        id: "ferrari-f355", name: "Ferrari F355 · 3.5L Flat-Plane V8", idleRPM: 1000, redlineRPM: 8500,
        softLimiterRPM: 8400, hardLimiterRPM: 8700, audioFolder: "Ferrari_F355", cylinders: 8, hasTurbo: false,
        audioReferences: [1000, 1800, 3200, 4500, 5900, 7100, 8300],
        soundDescription: "F355-inspired recreation · Metallic flat-plane exhaust"
    )
    static let carreraGT = EngineProfile(
        id: "porsche-carrera-gt", name: "Porsche Carrera GT · 5.7L V10", idleRPM: 900, redlineRPM: 8400,
        softLimiterRPM: 8300, hardLimiterRPM: 8600, audioFolder: "Porsche_Carrera_GT", cylinders: 10, hasTurbo: false,
        audioReferences: [900, 1800, 3100, 4400, 5800, 7000, 8200],
        soundDescription: "Carrera GT-inspired recreation · Raw V10 race character"
    )
    static let classics = [lexusLFA, murcielago, porsche996GT3, mazdaRX7, ferrariF355, carreraGT]
    static let available = [americanV8, bmwS65, supra2JZ, amgGTR] + classics
}
