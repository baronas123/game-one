import SceneKit
import simd

extension LaisvasKaklas {

    /// 3D treneris (SceneKit): galva, kaklas, pečiai, rankos. Stovi veidu į kamerą ir rodomas
    /// veidrodžiu – trenerio dešinė pusė ekrane dešinėje, kaip žaidėjo atspindys.
    /// Figūra – tai tu (galva juda kartu su tavo galva, kaip veidrodyje), o auksinis galvos kontūras
    /// rodo judesį: kur ir kaip nukreipti galvą. Kai taikinys pasiektas, kontūras tampa žalias.
    final class CoachRig {
        let scene = SCNScene()
        private let root = SCNNode()
        private let cameraNode = SCNNode()
        private let neckPivot = SCNNode()
        private let head = SCNNode()
        private let neck = SCNNode()
        private let ghostPivot = SCNNode()
        private let ghostMaterial = SCNMaterial()
        private var ghostMatched: Bool?
        private let shoulders: [SCNNode] = [SCNNode(), SCNNode()]
        private let upperArms: [SCNNode] = [SCNNode(), SCNNode()]
        private let forearms: [SCNNode] = [SCNNode(), SCNNode()]
        private let hands: [SCNNode] = [SCNNode(), SCNNode()]
        private let arrow = SCNNode()
        private var cameraAngle: Double?

        /// Kairė (−1) ir dešinė (+1) – indeksai 0 ir 1.
        private static let sides: [Float] = [-1, 1]
        private static let neckBase = SIMD3<Float>(0, 1.45, 0)
        private static let upperArm: Float = 0.27
        private static let forearm: Float = 0.25

        static let skin = CGColor(red: 0.96, green: 0.77, blue: 0.64, alpha: 1)
        static let shirt = CGColor(red: 0.33, green: 0.60, blue: 0.80, alpha: 1)
        static let hair = CGColor(red: 0.27, green: 0.19, blue: 0.21, alpha: 1)
        static let dark = CGColor(red: 0.14, green: 0.11, blue: 0.20, alpha: 1)
        static let lips = CGColor(red: 0.78, green: 0.40, blue: 0.40, alpha: 1)
        static let mint = CGColor(red: 0.45, green: 0.95, blue: 0.82, alpha: 1)
        static let gold = CGColor(red: 1.0, green: 0.80, blue: 0.40, alpha: 1)

        init() {
            scene.rootNode.addChildNode(root)
            buildBody()
            buildHead()
            buildGhost()
            buildArms()
            buildArrow()
            buildLights()
            buildCamera()
            apply(CoachPose(), ghost: nil, cameraAngle: 18, animated: false)
        }

        var pointOfView: SCNNode { cameraNode }

        // MARK: - Poza

        /// `ghost` – kontūro (taikinio) galvos poza (rankos nenaudojamos) arba nil – be kontūro.
        /// `cameraAngle` – iš kurios pusės žiūrime (0 – iš priekio, 90 – iš šono).
        /// `matched` – galva kontūre (kontūras žalias).
        func apply(_ pose: CoachPose, ghost: CoachPose?, matched: Bool = false, cameraAngle angle: Double,
                   animated: Bool = true) {
            // Galva: veidrodžiu, trenerio dešinė = +x.
            neckPivot.simdPosition = Self.neckBase + SIMD3(0, Float(0.01 * pose.chinBack), Float(-0.075 * pose.chinBack))
            neckPivot.simdOrientation = Self.headRotation(yaw: pose.yaw, pitch: pose.pitch + 4 * pose.chinBack, roll: pose.roll)
            let headBase = neckPivot.simdConvertPosition(SIMD3(0, 0.06, 0), to: root)
            Self.segment(neck, from: Self.neckBase - SIMD3(0, 0.04, 0), to: headBase, radius: 0.047)

            if let g = ghost {
                ghostPivot.isHidden = false
                if ghostMatched != matched {
                    ghostMatched = matched
                    ghostMaterial.diffuse.contents = matched ? Self.mint : Self.gold
                }
                ghostPivot.simdPosition = Self.neckBase + SIMD3(0, Float(0.01 * g.chinBack), Float(-0.075 * g.chinBack))
                ghostPivot.simdOrientation = Self.headRotation(yaw: g.yaw, pitch: g.pitch + 4 * g.chinBack, roll: g.roll)
            } else {
                ghostPivot.isHidden = true
            }

            // Pečiai
            for (i, sx) in Self.sides.enumerated() {
                shoulders[i].simdPosition = SIMD3(sx * 0.175, 1.40 + Float(0.06 * pose.shoulderUp), Float(-0.055 * pose.shoulderBack))
            }

            // Rankos
            for (i, sx) in Self.sides.enumerated() {
                let j = shoulders[i].simdPosition
                let rest = j + SIMD3(sx * 0.05, -0.47, 0.07)
                var target = rest
                var pole = SIMD3<Float>(sx, -0.5, -0.3)
                if let local = Self.handTarget(pose.hand, side: Int(sx)) {
                    let onHead = head.simdConvertPosition(local, to: root)
                    let k = Float(CoachDemo.ease(pose.handReach))
                    target = rest + (onHead - rest) * k
                    switch pose.hand {
                    case .overHead: pole = SIMD3(sx, 0.9 * k - 0.5 * (1 - k), -0.1)
                    // Alkūnė į priekį ir žemyn, kad ranka neuždengtų veido.
                    case .forehead: pole = SIMD3(sx * 1.2, -0.25, 0.7)
                    default: break
                    }
                }
                let elbow = Self.solveElbow(shoulder: j, hand: target, pole: pole)
                Self.segment(upperArms[i], from: j, to: elbow, radius: 0.038)
                Self.segment(forearms[i], from: elbow, to: target, radius: 0.032)
                hands[i].simdPosition = target
            }

            // Spaudimo rodyklė: iš už delno link galvos.
            if pose.press > 0.01, let (from, to) = arrowPoints(pose.hand) {
                arrow.isHidden = false
                let dir = simd_normalize(to - from)
                arrow.simdPosition = from - dir * Float(0.02 * pose.press)
                arrow.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: dir)
                arrow.opacity = CGFloat(0.5 + 0.5 * pose.press)
            } else {
                arrow.isHidden = true
            }

            if cameraAngle != angle {
                let first = cameraAngle == nil
                cameraAngle = angle
                SCNTransaction.begin()
                SCNTransaction.animationDuration = (animated && !first) ? 0.8 : 0
                placeCamera(angle)
                SCNTransaction.commit()
            }
        }

        /// Kampai laipsniais (žr. `CoachPose`) → sukimas kaklo pagrindo taške.
        private static func headRotation(yaw: Double, pitch: Double, roll: Double) -> simd_quatf {
            let r = Float.pi / 180
            let qYaw = simd_quatf(angle: Float(yaw) * r, axis: SIMD3(0, 1, 0))
            let qPitch = simd_quatf(angle: Float(pitch) * r, axis: SIMD3(1, 0, 0))
            let qRoll = simd_quatf(angle: Float(-roll) * r, axis: SIMD3(0, 0, 1))
            return qYaw * qRoll * qPitch
        }

        /// Delno vieta galvos koordinatėmis (galvos centras – 0), arba nil, jei ši ranka nuleista.
        private static func handTarget(_ hand: HandPlacement, side: Int) -> SIMD3<Float>? {
            switch hand {
            case .none: return nil
            case .forehead: return side > 0 ? SIMD3(0.01, 0.06, 0.15) : nil
            case .rightTemple: return side > 0 ? SIMD3(0.155, 0.03, 0.01) : nil
            case .leftTemple: return side < 0 ? SIMD3(-0.155, 0.03, 0.01) : nil
            case .backOfHead: return SIMD3(Float(side) * 0.04, 0.04, -0.15)
            case .overHead(let s): return side == s ? SIMD3(Float(-s) * 0.13, 0.08, 0.0) : nil
            }
        }

        private func arrowPoints(_ hand: HandPlacement) -> (SIMD3<Float>, SIMD3<Float>)? {
            let local: SIMD3<Float>
            switch hand {
            case .forehead: local = SIMD3(0, 0.06, 0.29)
            case .rightTemple: local = SIMD3(0.30, 0.03, 0.01)
            case .leftTemple: local = SIMD3(-0.30, 0.03, 0.01)
            case .backOfHead: local = SIMD3(0, 0.04, -0.30)
            default: return nil
            }
            let from = head.simdConvertPosition(local, to: root)
            let to = head.simdConvertPosition(SIMD3(0, 0.04, 0), to: root)
            return (from, to)
        }

        /// Dviejų kaulų IK: alkūnė pasirenkama `pole` kryptimi.
        private static func solveElbow(shoulder j: SIMD3<Float>, hand h: SIMD3<Float>, pole: SIMD3<Float>) -> SIMD3<Float> {
            let l1 = upperArm, l2 = forearm
            var v = h - j
            var d = simd_length(v)
            if d < 0.0001 { v = SIMD3(0, -1, 0); d = 0.0001 }
            let dir = v / d
            d = min(max(d, abs(l1 - l2) + 0.01), l1 + l2 - 0.001)
            let a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
            let hgt = sqrt(max(0, l1 * l1 - a * a))
            var p = pole - dir * simd_dot(pole, dir)
            if simd_length(p) < 0.0001 { p = SIMD3(0, 0, -1) }
            return j + dir * a + simd_normalize(p) * hgt
        }

        /// Kapsulė tarp dviejų taškų.
        private static func segment(_ node: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>, radius: CGFloat) {
            let v = b - a
            let len = max(0.001, simd_length(v))
            node.simdPosition = (a + b) / 2
            node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: v / len)
            if let c = node.geometry as? SCNCapsule {
                c.capRadius = radius
                c.height = CGFloat(len) + radius * 2
            }
        }

        // MARK: - Statyba

        private static func material(_ color: CGColor, rough: CGFloat = 0.6) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = color
            m.roughness.contents = rough
            m.metalness.contents = 0.0
            return m
        }

        private static func node(_ g: SCNGeometry, _ color: CGColor, at p: SIMD3<Float> = .zero,
                                 scale: SIMD3<Float> = SIMD3(1, 1, 1)) -> SCNNode {
            g.firstMaterial = material(color)
            let n = SCNNode(geometry: g)
            n.simdPosition = p
            n.simdScale = scale
            return n
        }

        private func buildBody() {
            // Liemuo: dvi suapvalintos „dėžės“ – krūtinė ir pilvas.
            root.addChildNode(Self.node(SCNBox(width: 0.36, height: 0.30, length: 0.21, chamferRadius: 0.10), Self.shirt,
                                        at: SIMD3(0, 1.28, 0)))
            root.addChildNode(Self.node(SCNBox(width: 0.31, height: 0.30, length: 0.19, chamferRadius: 0.09), Self.shirt,
                                        at: SIMD3(0, 1.06, 0)))
            root.addChildNode(Self.node(SCNTorus(ringRadius: 0.06, pipeRadius: 0.018), Self.shirt, at: SIMD3(0, 1.425, 0)))
            for i in 0..<2 {
                shoulders[i].geometry = SCNSphere(radius: 0.056)
                shoulders[i].geometry?.firstMaterial = Self.material(Self.shirt)
                root.addChildNode(shoulders[i])
            }
            neck.geometry = SCNCapsule(capRadius: 0.047, height: 0.2)
            neck.geometry?.firstMaterial = Self.material(Self.skin)
            root.addChildNode(neck)
        }

        private func buildHead() {
            root.addChildNode(neckPivot)
            head.simdPosition = SIMD3(0, 0.16, 0)
            neckPivot.addChildNode(head)

            head.addChildNode(Self.node(SCNSphere(radius: 0.105), Self.skin, scale: SIMD3(1, 1.15, 1)))
            // Plaukai: didesnė sfera, pastumta atgal ir į viršų – veidas lieka atviras.
            head.addChildNode(Self.node(SCNSphere(radius: 0.112), Self.hair, at: SIMD3(0, 0.035, -0.024),
                                        scale: SIMD3(1.02, 1, 1)))
            for sx in Self.sides {
                head.addChildNode(Self.node(SCNSphere(radius: 0.028), Self.skin, at: SIMD3(sx * 0.103, 0, -0.005),
                                            scale: SIMD3(0.5, 1, 0.8)))
                head.addChildNode(Self.node(SCNSphere(radius: 0.019), CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                                            at: SIMD3(sx * 0.038, 0.02, 0.088), scale: SIMD3(1.15, 0.85, 0.6)))
                head.addChildNode(Self.node(SCNSphere(radius: 0.011), Self.dark, at: SIMD3(sx * 0.038, 0.02, 0.1)))
                // Antakiai
                let brow = Self.node(SCNCapsule(capRadius: 0.006, height: 0.042), Self.hair,
                                     at: SIMD3(sx * 0.04, 0.052, 0.094))
                brow.simdOrientation = simd_quatf(angle: .pi / 2 - sx * 0.12, axis: SIMD3(0, 0, 1))
                head.addChildNode(brow)
                // Šypsena: dvi pusės, kampučiai pakelti.
                let smile = Self.node(SCNCapsule(capRadius: 0.007, height: 0.032), Self.lips,
                                      at: SIMD3(sx * 0.016, -0.058, 0.09))
                smile.simdOrientation = simd_quatf(angle: .pi / 2 + sx * 0.22, axis: SIMD3(0, 0, 1))
                head.addChildNode(smile)
            }
            head.addChildNode(Self.node(SCNSphere(radius: 0.019), Self.skin, at: SIMD3(0, -0.012, 0.103),
                                        scale: SIMD3(0.9, 1.1, 1.3)))
        }

        private func buildGhost() {
            root.addChildNode(ghostPivot)
            // Kontūras: galvos forma (kaukolė, ausys, nosis) – permatomas centras, švytintys kraštai
            // (Fresnel). Nosis ir ausys parodo, kur kontūras žiūri. Matosi ir per figūrą.
            let m = ghostMaterial
            m.lightingModel = .constant
            m.diffuse.contents = Self.gold
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            m.blendMode = .add
            m.shaderModifiers = [.fragment: """
            float rim = 1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view)));
            rim = pow(rim, 2.2);
            _output.color = float4(_output.color.rgb * (0.06 + 1.6 * rim), 1.0);
            """]
            let ghostHead = SCNNode()
            ghostHead.simdPosition = SIMD3(0, 0.16, 0)
            ghostHead.simdScale = SIMD3(repeating: 1.05)
            ghostPivot.addChildNode(ghostHead)
            func part(_ g: SCNGeometry, at p: SIMD3<Float>, scale: SIMD3<Float>) {
                g.firstMaterial = m
                let n = SCNNode(geometry: g)
                n.simdPosition = p
                n.simdScale = scale
                n.renderingOrder = 10
                ghostHead.addChildNode(n)
            }
            let skull = SCNSphere(radius: 0.108)
            skull.segmentCount = 48
            part(skull, at: .zero, scale: SIMD3(1, 1.15, 1))
            for sx in Self.sides {
                part(SCNSphere(radius: 0.03), at: SIMD3(sx * 0.106, 0, -0.005), scale: SIMD3(0.5, 1, 0.8))
            }
            part(SCNSphere(radius: 0.024), at: SIMD3(0, -0.012, 0.11), scale: SIMD3(0.9, 1.1, 1.4))
            ghostPivot.renderingOrder = 10
        }

        private func buildArms() {
            for i in 0..<2 {
                for (n, color) in [(upperArms[i], Self.shirt), (forearms[i], Self.skin)] {
                    n.geometry = SCNCapsule(capRadius: 0.04, height: 0.3)
                    n.geometry?.firstMaterial = Self.material(color)
                    root.addChildNode(n)
                }
                hands[i].geometry = SCNSphere(radius: 0.045)
                hands[i].geometry?.firstMaterial = Self.material(Self.skin)
                hands[i].simdScale = SIMD3(0.85, 1.1, 0.6)
                root.addChildNode(hands[i])
            }
        }

        private func buildArrow() {
            let m = Self.material(Self.gold, rough: 0.3)
            m.emission.contents = CGColor(red: 0.5, green: 0.35, blue: 0.1, alpha: 1)
            let shaft = SCNCylinder(radius: 0.012, height: 0.08)
            shaft.firstMaterial = m
            let tip = SCNCone(topRadius: 0, bottomRadius: 0.03, height: 0.05)
            tip.firstMaterial = m
            let s = SCNNode(geometry: shaft)
            s.simdPosition = SIMD3(0, 0.04, 0)
            let t = SCNNode(geometry: tip)
            t.simdPosition = SIMD3(0, 0.105, 0)
            arrow.addChildNode(s)
            arrow.addChildNode(t)
            arrow.isHidden = true
            root.addChildNode(arrow)
        }

        private func buildLights() {
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 450
            ambient.light?.color = CGColor(red: 0.75, green: 0.72, blue: 0.95, alpha: 1)
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 1100
            key.light?.color = CGColor(red: 1, green: 0.92, blue: 0.82, alpha: 1)
            key.simdOrientation = simd_quatf(angle: 0.5, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -0.6, axis: SIMD3(1, 0, 0))
            scene.rootNode.addChildNode(key)

            let rim = SCNNode()
            rim.light = SCNLight()
            rim.light?.type = .directional
            rim.light?.intensity = 650
            rim.light?.color = CGColor(red: 1, green: 0.62, blue: 0.45, alpha: 1)
            rim.simdOrientation = simd_quatf(angle: .pi * 0.85, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -0.3, axis: SIMD3(1, 0, 0))
            scene.rootNode.addChildNode(rim)
        }

        private func buildCamera() {
            let cam = SCNCamera()
            cam.fieldOfView = CGFloat(Self.fieldOfView)
            cam.zNear = 0.05
            cam.zFar = 20
            cameraNode.camera = cam
            scene.rootNode.addChildNode(cameraNode)
        }

        private static let cameraTarget = SIMD3<Float>(0, 1.50, 0)
        private static let cameraDistance: Float = 1.45
        private static let cameraElevation: Float = 0.28
        private static let fieldOfView: Float = 30

        /// Kur ekrane neutrali galva: centro aukštis ir spindulys – vaizdo aukščio dalimis
        /// (rodyklėms virš 3D vaizdo; kamera žiūri į tą patį tašką iš bet kurios pusės).
        static var headOnScreen: (y: Double, radius: Double) {
            let halfHeight = tan(fieldOfView / 2 * .pi / 180) * cameraDistance
            let dh = neckBase.y + 0.16 - cameraTarget.y
            let y = dh * cos(cameraElevation) / (halfHeight * 2)
            return (Double(0.5 - y), Double(0.115 / (halfHeight * 2)))
        }

        private func placeCamera(_ degrees: Double) {
            let a = Float(degrees) * .pi / 180
            let target = Self.cameraTarget
            let dist = Self.cameraDistance
            let elevation = Self.cameraElevation
            cameraNode.simdPosition = target + SIMD3(sin(a) * cos(elevation), sin(elevation), cos(a) * cos(elevation)) * dist
            cameraNode.simdLook(at: target)
        }
    }
}
