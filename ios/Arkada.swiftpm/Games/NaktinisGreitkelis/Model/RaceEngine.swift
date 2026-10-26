import Foundation

extension NaktinisGreitkelis {

    struct TrafficCar {
        var z: Double
        var offset: Double
        var speed: Double
        var colorIndex: Int
        var isTruck: Bool
    }

    enum RaceMode {
        case menu, countdown, play, ending, over, paused
    }

    enum RaceEvent {
        case crash, pickup, checkpoint(city: String, bonus: Int), start, gameOver
    }

    /// Ekrano projekcijos parametrai (priklauso nuo ekrano dydžio).
    struct Projection {
        var width: Double = 390
        var height: Double = 844
        var horizon: Double = 360
        var k: Double = 360
        var cameraHeight: Double = 1000
        var playerZ: Double = 840

        static let fieldOfView: Double = 100
        static let cameraDepth: Double = 1 / tan((fieldOfView / 2) * .pi / 180)

        init() {}

        init(width: Double, height: Double) {
            self.width = width
            self.height = height
            let portrait = height > width
            horizon = (height * (portrait ? 0.43 : 0.47)).rounded()
            k = (height - horizon) * (portrait ? 0.74 : 0.86)
            let halfRoadPx = width * (portrait ? 0.56 : 0.4)
            cameraHeight = Road.halfWidth * k / halfRoadPx
            playerZ = cameraHeight * Projection.cameraDepth
        }
    }

    /// Visa lenktynių logika – be SwiftUI. Tas pats algoritmas kaip web/naktinis-greitkelis.html.
    final class RaceEngine {
        static let maxSpeed: Double = Road.segmentLength * 60           // 12 000 vnt./s
        static let unitsPerKm: Double = 40_000
        static let checkpointGap: Double = 1100 * Road.segmentLength      // ~5,5 km tarp miestų
        static let cities = ["Grigiškės", "Vievis", "Elektrėnai", "Kaišiadorys", "Kaunas", "Ariogala",
                             "Kryžkalnis", "Rietavas", "Gargždai", "Klaipėda", "Palanga", "Šventoji"]

        private static let accel = maxSpeed / 4.5
        private static let decel = -maxSpeed / 5
        private static let brake = -maxSpeed
        private static let offRoadDecel = -maxSpeed / 1.6
        private static let offRoadLimit = maxSpeed / 3.2
        private static let centrifugal = 0.3
        static let carWidth: Double = 900 / Road.halfWidth

        let road = Road()
        private(set) var proj = Projection()

        private(set) var mode: RaceMode = .menu
        private(set) var position: Double = 0
        private(set) var speed: Double = 0
        private(set) var playerX: Double = 0
        private(set) var timeLeft: Double = 40
        private(set) var nitro: Double = 0.4
        private(set) var nitroOn = false
        private(set) var distance: Double = 0
        private(set) var checkpoint = 0
        private(set) var passed = 0
        private(set) var lap = 0
        private(set) var shake: Double = 0
        private(set) var crashFlash: Double = 0
        private(set) var pickupFlash: Double = 0
        private(set) var countdown: Double = 0
        private(set) var steerVisual: Double = 0
        private(set) var time: Double = 0
        private(set) var cars: [TrafficCar] = []
        private(set) var bannerTitle = ""
        private(set) var bannerSubtitle = ""
        private(set) var bannerUntil: Double = 0
        /// Fono paralakso poslinkiai (taškais).
        private(set) var farOffset: Double = 0
        private(set) var cityOffset: Double = 0
        /// Surinkti nitro balionai: segmento indeksas → ratas.
        private(set) var collected: [Int: Int] = [:]

        // Įvestis (nustato vaizdas)
        var touchSteer: Double = 0
        var tiltSteer: Double = 0
        var useTilt = false
        var nitroHeld = false
        var braking = false
        var reducedMotion = false
        /// Paskutinis matytas `TiltSensor.shakeCount` (kad kiekvienas purtymas suveiktų vieną kartą).
        var seenShakeCount = 0

        private var nitroBurst: Double = 0
        private var lastDate: Date?
        private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970))
        private(set) var events: [RaceEvent] = []

        init() {
            resetCars(count: 28)
        }

        var speedKmh: Int { Int((speed / RaceEngine.maxSpeed * 220).rounded()) }
        var km: Double { distance / RaceEngine.unitsPerKm }
        var kmToNext: Double { max(0, (Double(checkpoint + 1) * RaceEngine.checkpointGap - distance) / RaceEngine.unitsPerKm) }

        static func cityName(_ i: Int) -> String {
            let base = cities[i % cities.count]
            return i >= cities.count ? "\(base) · \(i / cities.count + 1) ratas" : base
        }

        var reachedCity: String { checkpoint > 0 ? RaceEngine.cities[(checkpoint - 1) % RaceEngine.cities.count] : "Vilnius" }

        // MARK: - Valdymas

        func layout(width: Double, height: Double) {
            if abs(proj.width - width) > 0.5 || abs(proj.height - height) > 0.5 {
                proj = Projection(width: width, height: height)
            }
        }

        func newRace() {
            position = 0; speed = 0; playerX = 0; timeLeft = 40; nitro = 0.4; distance = 0
            checkpoint = 0; passed = 0; lap = 0; shake = 0; crashFlash = 0; nitroBurst = 0
            countdown = 3; collected = [:]
            mode = .countdown
            resetCars(count: 34)
        }

        func pause() { if mode == .play || mode == .countdown { pausedFrom = mode; mode = .paused } }
        func resume() { if mode == .paused { mode = pausedFrom; lastDate = nil } }
        func quit() { if mode != .menu { mode = .over; events.append(.gameOver) } }
        func backToMenu() { mode = .menu }
        private var pausedFrom: RaceMode = .play

        /// Purtymas – trumpas nitro pliūpsnis.
        func shakeBoost() {
            if mode == .play && nitro > 0.05 {
                nitroBurst = 1.4
                banner("NITRO!", "supurtyta", 0.7)
            }
        }

        /// Paima ir išvalo įvykius (haptikai, garsui, ekranų keitimui).
        func drainEvents() -> [RaceEvent] {
            defer { events.removeAll() }
            return events
        }

        // MARK: - Ciklas

        func tick(_ date: Date) {
            let dt = min(0.05, lastDate.map { date.timeIntervalSince($0) } ?? 0)
            lastDate = date
            guard dt > 0, mode != .paused else { return }
            if mode == .menu || mode == .over {
                demo(dt)
            } else {
                update(dt)
            }
        }

        private func demo(_ dt: Double) {
            time += dt
            speed += (RaceEngine.maxSpeed * 0.55 - speed) * dt
            position = wrap(position + speed * dt)
            let seg = road.segment(at: position + proj.playerZ)
            playerX += (-seg.curve * 0.05 - playerX) * dt * 2
            for i in cars.indices { cars[i].z = wrap(cars[i].z + cars[i].speed * dt) }
            farOffset += seg.curve * 0.55 * dt * 18
            cityOffset += seg.curve * 0.55 * dt * 32
        }

        private func update(_ dt: Double) {
            time += dt
            let maxS = RaceEngine.maxSpeed
            if mode == .countdown {
                countdown -= dt
                if countdown <= 0 {
                    mode = .play
                    banner("VAŽIUOJAM!", "", 0.9)
                    events.append(.start)
                }
            }
            let playing = mode == .play
            let ending = mode == .ending
            let playerSeg = road.segment(at: position + proj.playerZ)
            let speedPct = speed / maxS
            let dx = dt * 2.2 * min(1, speedPct + 0.15)

            // nitro
            if nitroBurst > 0 { nitroBurst -= dt }
            nitroOn = playing && (nitroHeld || nitroBurst > 0) && nitro > 0
            if nitroOn { nitro = max(0, nitro - dt * 0.33) }
            let topSpeed = maxS * (nitroOn ? 1.45 : 1)

            // vairavimas: lietimas pirmenybinis, kitaip polinkis
            var steer = max(-1, min(1, touchSteer))
            if steer == 0 && useTilt { steer = max(-1, min(1, tiltSteer)) }
            if playing || ending { playerX += dx * steer }
            steerVisual += (steer - steerVisual) * min(1, dt * 10)
            playerX -= dx * speedPct * playerSeg.curve * RaceEngine.centrifugal

            // greitis
            if playing {
                speed += (braking ? RaceEngine.brake : RaceEngine.accel * (nitroOn ? 2 : 1)) * dt
            } else {
                speed += (ending ? RaceEngine.brake * 0.35 : RaceEngine.decel) * dt
            }
            if speed > topSpeed { speed += RaceEngine.decel * 2 * dt }
            if (playerX < -1 || playerX > 1) && speed > RaceEngine.offRoadLimit { speed += RaceEngine.offRoadDecel * dt }
            playerX = max(-2.4, min(2.4, playerX))
            speed = max(0, min(speed, maxS * 1.5))

            if playing {
                collide()
                for sprite in playerSeg.sprites where sprite.kind == .can {
                    if collected[playerSeg.index] != lap && abs(sprite.offset - playerX) < 0.32 {
                        collected[playerSeg.index] = lap
                        nitro = min(1, nitro + 0.34)
                        pickupFlash = 0.35
                        events.append(.pickup)
                    }
                }
            }

            // judėjimas
            let before = position
            position = wrap(position + speed * dt)
            if position < before { lap += 1 }
            distance += speed * dt

            // eismas
            let length = road.length
            for i in cars.indices {
                let prevRel = wrap(cars[i].z - (position + proj.playerZ))
                cars[i].z = wrap(cars[i].z + cars[i].speed * dt)
                let rel = wrap(cars[i].z - (position + proj.playerZ))
                if playing && prevRel < length / 2 && rel > length / 2 && rel > length - Road.segmentLength * 20 {
                    passed += 1
                }
            }

            // laikas ir miestai
            if playing {
                timeLeft -= dt
                let reached = Int(distance / RaceEngine.checkpointGap)
                if reached > checkpoint {
                    checkpoint = reached
                    let bonus = max(14, Int((30 - Double(checkpoint) * 1.4).rounded()))
                    timeLeft += Double(bonus)
                    let city = RaceEngine.cityName(checkpoint - 1)
                    banner(city.uppercased(), "+\(bonus) s", 1.8)
                    events.append(.checkpoint(city: city, bonus: bonus))
                    if cars.count < 90 {
                        for j in 0..<6 {
                            addCar(z: wrap(position + Double(60 + j * 40) * Road.segmentLength))
                        }
                    }
                }
                if timeLeft <= 0 {
                    timeLeft = 0
                    mode = .ending
                }
            }
            if ending && speed < 200 {
                mode = .over
                events.append(.gameOver)
            }

            farOffset += playerSeg.curve * speedPct * dt * 18
            cityOffset += playerSeg.curve * speedPct * dt * 32
            if shake > 0 { shake -= dt }
            if crashFlash > 0 { crashFlash -= dt }
            if pickupFlash > 0 { pickupFlash -= dt }
        }

        private func collide() {
            let length = road.length
            for car in cars {
                let dz = wrap(car.z - (position + proj.playerZ))
                let reach = (RaceEngine.carWidth * 2) * 0.42 * (car.isTruck ? 1.15 : 1)
                if dz < Road.segmentLength * 0.9 && speed > car.speed && abs(car.offset - playerX) < reach {
                    speed = car.speed * 0.55
                    let old = position
                    position = wrap(car.z - proj.playerZ - Road.segmentLength * 1.2)
                    var back = position - old
                    if back > length / 2 { back -= length } else if back < -length / 2 { back += length }
                    distance += back
                    shake = reducedMotion ? 0 : 0.45
                    crashFlash = 0.22
                    events.append(.crash)
                    return
                }
            }
        }

        // MARK: - Pagalbinės

        func wrap(_ v: Double) -> Double {
            let l = road.length
            var x = v.truncatingRemainder(dividingBy: l)
            if x < 0 { x += l }
            return x
        }

        func isCollected(segment index: Int) -> Bool { collected[index] == lap && mode != .menu }

        private func banner(_ title: String, _ subtitle: String, _ seconds: Double) {
            bannerTitle = title
            bannerSubtitle = subtitle
            bannerUntil = time + seconds
        }

        var bannerVisible: Bool { time < bannerUntil && mode != .menu && mode != .over }

        private func resetCars(count: Int) {
            cars = []
            let segs = road.segments.count
            for _ in 0..<count {
                addCar(z: Double(3000 + Int.random(in: 0..<max(1, segs - 3000), using: &rng)) * Road.segmentLength)
            }
        }

        private func addCar(z: Double) {
            cars.append(TrafficCar(
                z: z,
                offset: Road.laneOffsets[Int.random(in: 0..<3, using: &rng)] + Double.random(in: -0.05...0.05, using: &rng),
                speed: RaceEngine.maxSpeed * Double.random(in: 0.25...0.55, using: &rng),
                colorIndex: Int.random(in: 0..<7, using: &rng),
                isTruck: Double.random(in: 0..<1, using: &rng) < 0.2
            ))
        }
    }
}
