import Cocoa

// Поведение кота: нужды, выбор действия (Reflex/Utility), восприятие, исполнение состояний.
extension AppDelegate {
    func enter(_ s: St) {
        st = s; stTicks = 0; hopOffset = 0
        // гасим несовместимые намерения, чтобы не возникало невозможных комбинаций
        switch s {
        case .sleep, .zoomies, .hunt, .play:         // никаких миссий
            toFood = false; toPlay = false; goingAway = false; leaving = false; eating = false; eatingRef = nil
        case .idle:                                  // idle не «уходит»; еда выставляется отдельно после прихода
            goingAway = false; leaving = false
        case .walk:                                  // на ходу не грызём (toFood/goingAway ставит вызывающий)
            eating = false; eatingRef = nil
        case .digging, .away, .falling:
            break                                    // управляются своей логикой
        }
        switch s {
        case .sleep:   stDur = Int.random(in: 600...1600)
        case .idle:    stDur = Int.random(in: 40...110)
        case .walk:    stDur = 0
        case .digging: stDur = Int.random(in: 30...50)      // ~3–5 c копает
        case .away:    stDur = Int.random(in: 1800...6000)  // 3–10 мин гуляет
        case .falling: stDur = 0
        case .hunt:    stDur = 30
        case .play:    stDur = 8
        case .zoomies: stDur = 0; zoomReps = Int.random(in: 5...10)
                       targetX = Bool.random() ? leftEdge() : rightEdge()
        }
    }

    // центр БЛИЖАЙШЕЙ кучки: внутри кучи усредняем (встаёт по центру),
    // но между раздельными кучами не садится — идёт к ближайшей
    func foodTargetX() -> CGFloat? {
        let xs = kibbles.filter { $0.landed && !$0.dragging }.map { $0.x }.sorted()
        guard !xs.isEmpty else { return nil }
        var clusters: [[CGFloat]] = [[xs[0]]]
        for v in xs.dropFirst() {
            if v - clusters[clusters.count - 1].last! <= SIZE / 2 {   // тот же кластер
                clusters[clusters.count - 1].append(v)
            } else {
                clusters.append([v])                                   // новая кучка
            }
        }
        let centers = clusters.map { $0.reduce(0, +) / CGFloat($0.count) }
        return centers.min(by: { abs($0 - x) < abs($1 - x) })
    }

    func decideNext() {
        toFood = false; toPlay = false; goingAway = false; leaving = false   // свежее решение — без залипших намерений
        if hunger > EAT_HUNGER, let c = foodTargetX() {   // идёт к корму только если голоден
            toFood = true; targetX = c; enter(.walk); return
        }

        let hN = hunger                                     // 0..1 — насколько голоден
        let hour = Calendar.current.component(.hour, from: Date())
        let night = hour >= 23 || hour < 6                  // ночью спит крепче
        let crep = (hour >= 6 && hour < 9) || (hour >= 18 && hour < 22)  // сумерки — пик активности

        // веса действий по потребностям и времени суток
        var wSleep = (1.4 - energy) + (night ? 1.4 : 0.3)        // устал/ночь → спать
        var wWalk = 0.5 + boredom * 0.9 + energy * 0.3          // скучно/бодр → бродить
        var wZoom = max(0, boredom * energy * (0.4 + hN)) * (crep ? 2.0 : 0.5) // → носиться
        var wIdle = 0.5                                         // посидеть/умыться

        // настроение дня меняет акценты
        switch mood {
        case .playful: wZoom *= 2.2; wWalk *= 1.4; wSleep *= 0.7
        case .lazy:    wSleep *= 1.7; wWalk *= 0.6; wZoom *= 0.4
        case .curious: wWalk *= 1.8; wIdle *= 0.7
        case .hungry:  wZoom *= 1.5; wWalk *= 1.2
        case .normal:  break
        }

        let weights: [(St, Double)] = [(.sleep, wSleep), (.walk, wWalk), (.zoomies, wZoom), (.idle, wIdle)]
        let total = weights.reduce(0) { $0 + max(0, $1.1) }
        var pick = St.idle
        if total > 0 {                                  // гард: пустой/некорректный набор весов → idle
            var r = Double.random(in: 0..<total)
            for (s, w) in weights { if r < max(0, w) { pick = s; break }; r -= max(0, w) }
        }

        let awayChance = (mood == .curious) ? 0.16 : 0.07       // любопытный чаще уходит «за стену»
        switch pick {
        case .zoomies:
            enter(.zoomies)
        case .walk:
            if Double.random(in: 0..<1) < awayChance {          // своенравно уходит за стену
                goingAway = true; awayLeft = Bool.random()
                targetX = awayLeft ? leftEdge() : rightEdge()
                enter(.walk)
            } else {
                targetX = randomX(); enter(.walk)
            }
        case .sleep:
            enter(.sleep)
        default:
            enter(.idle)
        }
    }

    // ——— Utility-мозг: нужды через response-кривые → взвешенный выбор с инерцией ———
    func ramp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {   // piecewise-linear 0..1
        if v <= lo { return 0 }; if v >= hi { return 1 }; return (v - lo) / (hi - lo)
    }

    func utilityDecide() {
        toFood = false; toPlay = false; goingAway = false; leaving = false
        if hunger > EAT_HUNGER, let c = foodTargetX() { toFood = true; targetX = c; enter(.walk); return }

        let hour = Calendar.current.component(.hour, from: Date())
        let night = hour >= 23 || hour < 6
        let crep = (hour >= 6 && hour < 9) || (hour >= 18 && hour < 22)

        // полезности из нужд (response-кривые: «игнорить до порога, потом расти»)
        var uSleep = ramp(1 - energy, 0.35, 0.95) * (night ? 1.4 : 0.7)   // спит, когда реально устал
        var uWalk  = 0.7 + ramp(boredom, 0.05, 0.7) * 1.0 + energy * 0.2  // спокойная прогулка — частая
        var uZoom  = ramp(boredom, 0.6, 1.0) * energy * (crep ? 1.0 : 0.3) // беготня — реже, когда очень бодр и скучно
        var uIdle  = 0.6                                                  // посидеть/умыться

        switch mood {
        case .playful: uZoom *= 1.8; uWalk *= 1.3; uSleep *= 0.8
        case .lazy:    uSleep *= 1.6; uWalk *= 0.7; uZoom *= 0.4
        case .curious: uWalk *= 1.6; uIdle *= 0.7
        case .hungry:  uZoom *= 1.3; uWalk *= 1.2
        case .normal:  break
        }

        // лёгкая инерция активным состояниям (но НЕ сну — иначе пересыпает)
        switch st {
        case .walk:    uWalk *= 1.15
        case .zoomies: uZoom *= 1.1
        case .idle:    uIdle *= 1.1
        default: break
        }

        let weights: [(St, Double)] = [(.sleep, uSleep), (.walk, uWalk), (.zoomies, uZoom), (.idle, uIdle)]
        let total = weights.reduce(0) { $0 + max(0, $1.1) }
        var pick = St.idle
        if total > 0 {
            var r = Double.random(in: 0..<total)
            for (s, w) in weights { if r < max(0, w) { pick = s; break }; r -= max(0, w) }
        }

        let awayChance = (mood == .curious) ? 0.16 : 0.07
        switch pick {
        case .zoomies: enter(.zoomies)
        case .walk:
            if Double.random(in: 0..<1) < awayChance {
                goingAway = true; awayLeft = Bool.random()
                targetX = awayLeft ? leftEdge() : rightEdge()
                enter(.walk)
            } else { targetX = randomX(); enter(.walk) }
        case .sleep: enter(.sleep)
        default: enter(.idle)
        }
    }

    // Один тик: общая «преамбула» (нужды + привлечение корма) + исполнение состояния.
    // Решение «что дальше» инъектируется: Reflex → рандом, Utility → нужды/полезность.
    func reflexStep()  { stepPreamble(); runState(decide: { self.decideNext() }) }
    func utilityStep() {
        stepPreamble()
        if huntCool > 0 { huntCool -= 1 }
        perceive()                                   // охота на курсор (только Utility)
        playAttract()                                // гоняется за клубком (только Utility)
        runState(decide: { self.utilityDecide() })
    }

    // Восприятие окружения: мышь прямо НАД котом в зоне досягаемости → вертикальный подскок.
    func perceive() {
        guard huntCool == 0, !eating, !toFood, !goingAway, !leaving,
              st == .idle || st == .walk || st == .zoomies else { hoverTicks = 0; return }
        let m = NSEvent.mouseLocation
        let above = m.y - y                         // насколько мышь выше кота
        if abs(m.x - x) < 70 && above > 30 && above < 260 {   // над котом и в досягаемости
            hoverTicks += 1
            if hoverTicks >= 6 {                    // мышь именно ЗАВИСЛА (~0.6с), а не пролетела
                hoverTicks = 0
                huntHopH = min(above, 150)          // подпрыгнуть к ней (с потолком)
                enter(.hunt)
            }
        } else {
            hoverTicks = 0
        }
    }

    // Игра с клубком: если клубок есть и кот не очень устал — всегда бежит к нему
    // (пока клубок не надоест). Еда в приоритете.
    func playAttract() {
        guard let k = yarn, !k.dragging, !eating, !toFood, !goingAway, !leaving,
              energy > 0.22, !playTired else {           // устал или наигрался — не бежит
            if st != .walk { toPlay = false }; return
        }
        switch st {
        case .walk:                   if toPlay { targetX = k.x }   // уже бежим — правим цель
        case .idle, .zoomies, .sleep: toPlay = true; targetX = k.x; enter(.walk)   // даже разбудит
        default: break
        }
    }

    // Мягкий толчок лапой, по очереди в разные стороны — клубок катается рядом, не улетает.
    func batYarn() {
        guard let k = yarn else { return }
        k.vx = playDir * CGFloat.random(in: 4...8)
        k.vy = 5; k.landed = false
        playDir = -playDir                          // следующий раз — в другую сторону
        boredom = max(0, boredom - 0.05)            // игра развлекает
        playSat = min(1, playSat + 0.05)            // и понемногу надоедает
        if playSat >= 0.85 { playTired = true }     // наигрался — пойдёт отдыхать
    }

    func stepPreamble() {
        y = bottomY()
        stTicks += 1
        hunger = min(1, hunger + HUNGER_RATE * (mood == .hungry ? 2 : 1))  // голод растёт медленно (~8 ч)
        playSat = max(0, playSat - 0.0012)   // интерес к клубку понемногу восстанавливается
        if playSat <= 0.4 { playTired = false }   // отдохнул — снова можно играть (гистерезис)

        // потребности: энергия и скука дрейфуют по состоянию
        switch st {
        case .sleep:                 energy = min(1, energy + 0.0008); boredom = min(1, boredom + 0.0004)
        case .walk, .zoomies, .hunt: energy = max(0, energy - 0.0016); boredom = max(0, boredom - 0.0025)
        case .digging, .away:        boredom = max(0, boredom - 0.0015)   // прогулка тоже развлекает
        case .idle:                  energy = min(1, energy + 0.0003); boredom = min(1, boredom + 0.0007)
        default: break
        }

        // корм привлекает — прерывает беготню/ходьбу/сидение (но не сон/уход)
        if hunger > EAT_HUNGER && !eating && !goingAway && !leaving, let c = foodTargetX() {
            switch st {
            case .walk:
                toFood = true; toPlay = false; targetX = c   // еда важнее игры
            case .zoomies, .idle:
                toFood = true; toPlay = false; targetX = c; enter(.walk)
            default: break
            }
        }
    }

    func runState(decide: () -> Void) {
        var img: NSImage
        switch st {
        case .zoomies:
            let tx = targetX ?? x
            let dx = tx - x
            if abs(dx) <= ZOOM {
                x = tx
                zoomReps -= 1
                if zoomReps <= 0 { enter(.idle); img = frame("idle", 0) }
                else { targetX = (tx <= leftEdge() + 1) ? rightEdge() : leftEdge()
                       img = frame(dx > 0 ? "E" : "W", anim) }
            } else {
                x += dx > 0 ? ZOOM : -ZOOM
                img = frame(dx > 0 ? "E" : "W", anim)
            }
        case .walk:
            let sp: CGFloat = toFood ? FOOD_SPEED : SPEED
            let tx = targetX ?? x
            let dx = tx - x
            if abs(dx) <= sp {
                x = tx
                if leaving { leaving = false; win.orderOut(nil); enter(.away); img = frame("idle", 0) }
                else if goingAway { enter(.digging); img = frame(awayLeft ? "digL" : "digR", 0) }
                else if toPlay { toPlay = false; batYarn(); enter(.play); img = frame("held", 0) }
                else { toFood = false; eatNearbyKibble(); enter(.idle); img = frame("idle", 0) }
            } else {
                x += dx > 0 ? sp : -sp
                img = frame(dx > 0 ? "E" : "W", anim / 3)   // свободный счётчик — не застывает при смене цели
            }
        case .digging:
            img = frame(awayLeft ? "digL" : "digR", stTicks / 5)   // копает дырку
            if stTicks > stDur {                    // прокопал → уходит за край шагами
                leaving = true; goingAway = false
                targetX = awayLeft ? leftEdge() - SIZE : rightEdge() + SIZE
                enter(.walk)
            }
        case .away:
            img = frame("idle", 0)                  // не виден
            if stTicks > stDur {                    // возвращается из-за края шагами
                goingAway = false; leaving = false
                x = awayLeft ? leftEdge() - SIZE : rightEdge() + SIZE
                y = bottomY()
                win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2))
                win.orderFrontRegardless()
                targetX = randomX(); toFood = false; enter(.walk)
            }
        case .idle:
            if eating {
                if let k = eatingRef, k.landed, !k.dragging, abs(k.x - x) <= SIZE / 2 {   // лежит рядом, не схвачен
                    img = frame("eat", 0)
                    biteTick += 1
                    if biteTick >= 16 {             // очередной укус
                        biteTick = 0
                        k.eaten += 1
                        hunger = max(0, hunger - SATIATION / Double(k.maxBites))  // сытость от каждого укуса
                        k.dot.stage = min(KibbleDot.stages.count - 1,
                                          Int(Double(k.eaten) / Double(k.maxBites) * Double(KibbleDot.stages.count)))
                        if k.eaten >= k.maxBites {  // доел этот катышек
                            k.win.orderOut(nil)
                            kibbles.removeAll { $0 === k }
                            eatingRef = nil; eating = false
                            if hunger > FULL, let c = foodTargetX() {   // ещё не наелся и есть корм — к следующему
                                toFood = true; targetX = c; enter(.walk)
                            } else {
                                decide()
                            }
                        }
                    }
                } else {                            // схватили/улетел — перестаём есть
                    eating = false; eatingRef = nil; img = frame("idle", 0)
                }
            } else {
                if stTicks > stDur / 4 && stTicks < stDur * 3 / 4 {
                    img = frame("scratch", stTicks / 4)     // умывается
                } else {
                    img = frame("idle", 0)
                }
                if stTicks > stDur { decide() }
            }
        case .sleep:
            img = frame("sleep", stTicks / 8)
            if stTicks > stDur { decide() }                 // ест только когда сам проснулся
        case .hunt:
            if stTicks < 7 {                                // присел перед прыжком
                img = frame("alert", 0)
            } else if stTicks < 17 {                        // вертикальный подскок к курсору (без сдвига вбок)
                hopOffset = CGFloat(sin(Double(stTicks - 7) / 10.0 * .pi)) * huntHopH
                img = frame("fall", anim / 2)               // лапы врастопырку — в прыжке
                let m = NSEvent.mouseLocation
                if abs(m.x - x) < 45 && abs(m.y - (y + hopOffset)) < 55 {   // достал курсор — цепляется!
                    clinging = true; hopOffset = 0
                }
            } else {                                        // приземлился
                hopOffset = 0; huntCool = 12
                boredom = max(0, boredom - 0.15)            // охота развлекает — снижает скуку
                enter(.idle); img = frame("idle", 0)
            }
        case .play:
            img = frame("held", anim / 3)                   // лапками по клубку — как при подвешивании
            if stTicks > stDur { enter(.idle) }
        case .falling:
            img = frame("held", 0)                          // (обрабатывается выше)
        }
        iv.image = img
        let drop: CGFloat = eating ? 6 : 0   // когда ест — садится ниже, чтоб попа не висела
        win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2 - drop + hopOffset))
        anim += 1
    }
}
