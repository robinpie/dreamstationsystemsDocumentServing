// Multiplayer WebRTC Module for Wiktionary Racing
// Uses peer-to-peer connections with manual code exchange (no server required)

const Multiplayer = (function() {
    // State
    let localPeerId = null;
    let isHost = false;
    let peers = new Map(); // peerId -> { connection, dataChannel, playerData }
    let lobbyState = {
        players: [], // { id, name, color, isHost, isReady, currentWord, path, clickCount, finished, finishTime }
        startWord: null,
        targetWord: null,
        gameStarted: false,
        countdown: null
    };
    let localPlayerName = 'Player';
    let localPlayerColor = '#5BA3E8';
    let onStateChangeCallback = null;
    let pendingConnections = new Map(); // For handling incoming connection offers

    // Generate a unique peer ID
    function generatePeerId() {
        return 'p_' + Math.random().toString(36).substr(2, 9);
    }

    // Generate player colors
    const playerColors = [
        '#5BA3E8', '#6BCF7F', '#F59E0B', '#EF4444', '#8B5CF6', '#EC4899', '#14B8A6', '#F97316'
    ];

    function getPlayerColor(index) {
        return playerColors[index % playerColors.length];
    }

    // Encode/decode connection data for sharing
    function encodeConnectionData(data) {
        return btoa(JSON.stringify(data));
    }

    function decodeConnectionData(encoded) {
        try {
            return JSON.parse(atob(encoded));
        } catch (e) {
            console.error('Failed to decode connection data:', e);
            return null;
        }
    }

    // Create RTCPeerConnection with STUN servers
    function createPeerConnection(peerId) {
        const config = {
            iceServers: [
                { urls: 'stun:stun.l.google.com:19302' },
                { urls: 'stun:stun1.l.google.com:19302' },
                { urls: 'stun:stun2.l.google.com:19302' }
            ]
        };

        const pc = new RTCPeerConnection(config);

        pc.onicecandidate = (event) => {
            if (event.candidate) {
                // ICE candidate gathered - we'll include all candidates in the offer/answer
            }
        };

        pc.onconnectionstatechange = () => {
            console.log(`Connection state for ${peerId}:`, pc.connectionState);
            if (pc.connectionState === 'disconnected' || pc.connectionState === 'failed') {
                handlePeerDisconnect(peerId);
            }
        };

        return pc;
    }

    // Host: Create a room and generate invite code
    async function createRoom(playerName) {
        localPeerId = generatePeerId();
        isHost = true;
        localPlayerName = playerName || 'Host';
        localPlayerColor = getPlayerColor(0);

        // Initialize lobby with host
        lobbyState = {
            players: [{
                id: localPeerId,
                name: localPlayerName,
                color: localPlayerColor,
                isHost: true,
                isReady: false,
                currentWord: null,
                path: [],
                clickCount: 0,
                finished: false,
                finishTime: null
            }],
            startWord: null,
            targetWord: null,
            gameStarted: false,
            countdown: null
        };

        notifyStateChange();

        // Create initial offer data that guests will use
        const roomData = {
            type: 'room',
            hostId: localPeerId,
            hostName: localPlayerName
        };

        return encodeConnectionData(roomData);
    }

    // Guest: Join a room using host's code
    async function joinRoom(hostCode, playerName) {
        const roomData = decodeConnectionData(hostCode);
        if (!roomData || roomData.type !== 'room') {
            throw new Error('Invalid room code');
        }

        localPeerId = generatePeerId();
        isHost = false;
        localPlayerName = playerName || 'Guest';
        localPlayerColor = getPlayerColor(1);

        // Create peer connection to host
        const pc = createPeerConnection(roomData.hostId);

        // Create data channel
        const dataChannel = pc.createDataChannel('game', { ordered: true });
        setupDataChannel(dataChannel, roomData.hostId);

        // Create offer
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        // Wait for ICE gathering to complete
        await waitForIceGathering(pc);

        // Store the connection
        peers.set(roomData.hostId, {
            connection: pc,
            dataChannel: dataChannel,
            playerData: {
                id: roomData.hostId,
                name: roomData.hostName,
                isHost: true
            }
        });

        // Generate join code for host
        const joinData = {
            type: 'join',
            peerId: localPeerId,
            playerName: localPlayerName,
            offer: pc.localDescription
        };

        return encodeConnectionData(joinData);
    }

    // Host: Accept a guest's join request
    async function acceptJoin(joinCode) {
        const joinData = decodeConnectionData(joinCode);
        if (!joinData || joinData.type !== 'join') {
            throw new Error('Invalid join code');
        }

        const pc = createPeerConnection(joinData.peerId);

        // Handle incoming data channel
        pc.ondatachannel = (event) => {
            setupDataChannel(event.channel, joinData.peerId);
            peers.get(joinData.peerId).dataChannel = event.channel;
        };

        // Set remote description (the offer)
        await pc.setRemoteDescription(new RTCSessionDescription(joinData.offer));

        // Create answer
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        // Wait for ICE gathering
        await waitForIceGathering(pc);

        // Store the connection
        const playerColor = getPlayerColor(lobbyState.players.length);
        peers.set(joinData.peerId, {
            connection: pc,
            dataChannel: null, // Will be set when ondatachannel fires
            playerData: {
                id: joinData.peerId,
                name: joinData.playerName,
                color: playerColor,
                isHost: false,
                isReady: false,
                currentWord: null,
                path: [],
                clickCount: 0,
                finished: false,
                finishTime: null
            }
        });

        // Add player to lobby
        lobbyState.players.push(peers.get(joinData.peerId).playerData);

        // Broadcast updated lobby state to all peers
        broadcastLobbyState();
        notifyStateChange();

        // Generate accept code for guest
        const acceptData = {
            type: 'accept',
            peerId: localPeerId,
            answer: pc.localDescription,
            lobbyState: lobbyState,
            yourColor: playerColor
        };

        return encodeConnectionData(acceptData);
    }

    // Guest: Complete connection with host's accept code
    async function completeJoin(acceptCode) {
        const acceptData = decodeConnectionData(acceptCode);
        if (!acceptData || acceptData.type !== 'accept') {
            throw new Error('Invalid accept code');
        }

        const peer = peers.get(acceptData.peerId);
        if (!peer) {
            throw new Error('No pending connection found');
        }

        // Set remote description (the answer)
        await peer.connection.setRemoteDescription(new RTCSessionDescription(acceptData.answer));

        // Update local state with lobby data from host
        lobbyState = acceptData.lobbyState;
        localPlayerColor = acceptData.yourColor;

        // Add self to players if not already there
        const selfInLobby = lobbyState.players.find(p => p.id === localPeerId);
        if (!selfInLobby) {
            lobbyState.players.push({
                id: localPeerId,
                name: localPlayerName,
                color: localPlayerColor,
                isHost: false,
                isReady: false,
                currentWord: null,
                path: [],
                clickCount: 0,
                finished: false,
                finishTime: null
            });
        }

        notifyStateChange();
    }

    // Wait for ICE gathering to complete (with timeout)
    function waitForIceGathering(pc) {
        return new Promise((resolve) => {
            if (pc.iceGatheringState === 'complete') {
                resolve();
                return;
            }

            const timeout = setTimeout(() => {
                resolve(); // Proceed even if not all candidates gathered
            }, 3000);

            pc.onicegatheringstatechange = () => {
                if (pc.iceGatheringState === 'complete') {
                    clearTimeout(timeout);
                    resolve();
                }
            };
        });
    }

    // Setup data channel event handlers
    function setupDataChannel(channel, peerId) {
        channel.onopen = () => {
            console.log(`Data channel opened with ${peerId}`);
            if (!isHost) {
                // Guest sends their info to host
                sendToPeer(peerId, {
                    type: 'player-info',
                    player: {
                        id: localPeerId,
                        name: localPlayerName,
                        color: localPlayerColor
                    }
                });
            }
        };

        channel.onclose = () => {
            console.log(`Data channel closed with ${peerId}`);
            handlePeerDisconnect(peerId);
        };

        channel.onerror = (error) => {
            console.error(`Data channel error with ${peerId}:`, error);
        };

        channel.onmessage = (event) => {
            try {
                const message = JSON.parse(event.data);
                handleMessage(peerId, message);
            } catch (e) {
                console.error('Failed to parse message:', e);
            }
        };
    }

    // Handle incoming messages
    function handleMessage(fromPeerId, message) {
        switch (message.type) {
            case 'player-info':
                // Update player info
                const player = lobbyState.players.find(p => p.id === message.player.id);
                if (player) {
                    Object.assign(player, message.player);
                }
                if (isHost) {
                    broadcastLobbyState();
                }
                notifyStateChange();
                break;

            case 'lobby-state':
                // Full lobby state sync from host
                lobbyState = message.state;
                notifyStateChange();
                break;

            case 'ready-toggle':
                if (isHost) {
                    const p = lobbyState.players.find(pl => pl.id === fromPeerId);
                    if (p) {
                        p.isReady = message.isReady;
                        broadcastLobbyState();
                        notifyStateChange();
                    }
                }
                break;

            case 'game-start':
                lobbyState.gameStarted = true;
                lobbyState.startWord = message.startWord;
                lobbyState.targetWord = message.targetWord;
                lobbyState.countdown = message.countdown;
                notifyStateChange();
                break;

            case 'countdown-tick':
                lobbyState.countdown = message.countdown;
                notifyStateChange();
                break;

            case 'game-begin':
                lobbyState.countdown = null;
                // Initialize all players' current word
                lobbyState.players.forEach(p => {
                    p.currentWord = lobbyState.startWord;
                    p.path = [lobbyState.startWord];
                    p.clickCount = 0;
                    p.finished = false;
                    p.finishTime = null;
                });
                notifyStateChange();
                break;

            case 'player-move':
                // Update a player's current position
                const movingPlayer = lobbyState.players.find(p => p.id === message.playerId);
                if (movingPlayer) {
                    movingPlayer.currentWord = message.currentWord;
                    movingPlayer.path = message.path;
                    movingPlayer.clickCount = message.clickCount;
                }
                if (isHost) {
                    // Relay to other peers
                    broadcastExcept(fromPeerId, message);
                }
                notifyStateChange();
                break;

            case 'player-finish':
                const finishingPlayer = lobbyState.players.find(p => p.id === message.playerId);
                if (finishingPlayer) {
                    finishingPlayer.finished = true;
                    finishingPlayer.finishTime = message.finishTime;
                    finishingPlayer.clickCount = message.clickCount;
                    finishingPlayer.path = message.path;
                }
                if (isHost) {
                    broadcastExcept(fromPeerId, message);
                }
                notifyStateChange();
                break;

            case 'player-disconnect':
                handlePeerDisconnect(message.playerId);
                break;

            default:
                console.warn('Unknown message type:', message.type);
        }
    }

    // Send message to specific peer
    function sendToPeer(peerId, message) {
        const peer = peers.get(peerId);
        if (peer && peer.dataChannel && peer.dataChannel.readyState === 'open') {
            peer.dataChannel.send(JSON.stringify(message));
        }
    }

    // Broadcast to all peers
    function broadcast(message) {
        peers.forEach((peer, peerId) => {
            sendToPeer(peerId, message);
        });
    }

    // Broadcast to all peers except one
    function broadcastExcept(excludePeerId, message) {
        peers.forEach((peer, peerId) => {
            if (peerId !== excludePeerId) {
                sendToPeer(peerId, message);
            }
        });
    }

    // Broadcast lobby state to all peers
    function broadcastLobbyState() {
        broadcast({
            type: 'lobby-state',
            state: lobbyState
        });
    }

    // Handle peer disconnect
    function handlePeerDisconnect(peerId) {
        const peer = peers.get(peerId);
        if (peer) {
            if (peer.connection) {
                peer.connection.close();
            }
            peers.delete(peerId);
        }

        // Remove from lobby
        lobbyState.players = lobbyState.players.filter(p => p.id !== peerId);

        if (isHost) {
            broadcastLobbyState();
        }

        notifyStateChange();
    }

    // Toggle ready state
    function toggleReady() {
        const self = lobbyState.players.find(p => p.id === localPeerId);
        if (self) {
            self.isReady = !self.isReady;
            if (isHost) {
                broadcastLobbyState();
                notifyStateChange();
            } else {
                // Send to host
                peers.forEach((peer, peerId) => {
                    sendToPeer(peerId, {
                        type: 'ready-toggle',
                        isReady: self.isReady
                    });
                });
            }
        }
    }

    // Host: Set challenge words
    function setChallengeWords(startWord, targetWord) {
        if (!isHost) return;
        lobbyState.startWord = startWord;
        lobbyState.targetWord = targetWord;
        broadcastLobbyState();
        notifyStateChange();
    }

    // Host: Start the game with countdown
    function startGame() {
        if (!isHost) return;
        if (!lobbyState.startWord || !lobbyState.targetWord) return;

        // Check if all players are ready (except host)
        const allReady = lobbyState.players.every(p => p.isHost || p.isReady);
        if (!allReady) return;

        lobbyState.gameStarted = true;
        lobbyState.countdown = 3;

        // Broadcast game start
        broadcast({
            type: 'game-start',
            startWord: lobbyState.startWord,
            targetWord: lobbyState.targetWord,
            countdown: 3
        });

        notifyStateChange();

        // Countdown
        let count = 3;
        const countdownInterval = setInterval(() => {
            count--;
            lobbyState.countdown = count;
            broadcast({
                type: 'countdown-tick',
                countdown: count
            });
            notifyStateChange();

            if (count <= 0) {
                clearInterval(countdownInterval);
                lobbyState.countdown = null;

                // Initialize all players
                lobbyState.players.forEach(p => {
                    p.currentWord = lobbyState.startWord;
                    p.path = [lobbyState.startWord];
                    p.clickCount = 0;
                    p.finished = false;
                    p.finishTime = null;
                });

                broadcast({
                    type: 'game-begin'
                });
                notifyStateChange();
            }
        }, 1000);
    }

    // Report local player movement
    function reportMove(currentWord, path, clickCount) {
        const self = lobbyState.players.find(p => p.id === localPeerId);
        if (self) {
            self.currentWord = currentWord;
            self.path = path;
            self.clickCount = clickCount;
        }

        broadcast({
            type: 'player-move',
            playerId: localPeerId,
            currentWord: currentWord,
            path: path,
            clickCount: clickCount
        });

        notifyStateChange();
    }

    // Report local player finished
    function reportFinish(finishTime, clickCount, path) {
        const self = lobbyState.players.find(p => p.id === localPeerId);
        if (self) {
            self.finished = true;
            self.finishTime = finishTime;
            self.clickCount = clickCount;
            self.path = path;
        }

        broadcast({
            type: 'player-finish',
            playerId: localPeerId,
            finishTime: finishTime,
            clickCount: clickCount,
            path: path
        });

        notifyStateChange();
    }

    // Leave the multiplayer session
    function leave() {
        broadcast({
            type: 'player-disconnect',
            playerId: localPeerId
        });

        // Close all connections
        peers.forEach((peer) => {
            if (peer.connection) {
                peer.connection.close();
            }
        });

        // Reset state
        peers.clear();
        localPeerId = null;
        isHost = false;
        lobbyState = {
            players: [],
            startWord: null,
            targetWord: null,
            gameStarted: false,
            countdown: null
        };

        notifyStateChange();
    }

    // Set callback for state changes
    function onStateChange(callback) {
        onStateChangeCallback = callback;
    }

    function notifyStateChange() {
        if (onStateChangeCallback) {
            onStateChangeCallback({
                isHost: isHost,
                localPeerId: localPeerId,
                lobbyState: lobbyState,
                isConnected: peers.size > 0 || isHost
            });
        }
    }

    // Get current state
    function getState() {
        return {
            isHost: isHost,
            localPeerId: localPeerId,
            lobbyState: lobbyState,
            isConnected: peers.size > 0 || isHost
        };
    }

    // ==================== DEBUG: FAKE PLAYERS ====================

    const fakePlayerNames = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace', 'Henry'];
    let fakePlayerIntervals = new Map(); // Store intervals for fake player movements

    // Add a fake player to the lobby
    function addFakePlayer() {
        if (!isHost) return null;

        const fakeId = 'fake_' + Math.random().toString(36).substr(2, 9);
        const usedNames = lobbyState.players.map(p => p.name);
        const availableNames = fakePlayerNames.filter(n => !usedNames.includes(n));
        const fakeName = availableNames.length > 0
            ? availableNames[Math.floor(Math.random() * availableNames.length)]
            : 'Bot ' + (lobbyState.players.length);
        const fakeColor = getPlayerColor(lobbyState.players.length);

        const fakePlayer = {
            id: fakeId,
            name: fakeName,
            color: fakeColor,
            isHost: false,
            isReady: true, // Fake players are always ready
            isFake: true,
            currentWord: null,
            path: [],
            clickCount: 0,
            finished: false,
            finishTime: null
        };

        lobbyState.players.push(fakePlayer);
        notifyStateChange();

        return fakeId;
    }

    // Start fake player simulation during game
    function startFakePlayerSimulation() {
        const fakePlayers = lobbyState.players.filter(p => p.isFake);

        fakePlayers.forEach(fakePlayer => {
            // Initialize fake player
            fakePlayer.currentWord = lobbyState.startWord;
            fakePlayer.path = [lobbyState.startWord];
            fakePlayer.clickCount = 0;
            fakePlayer.finished = false;
            fakePlayer.finishTime = null;

            // Random delay between moves (2-6 seconds)
            const simulateMove = () => {
                if (fakePlayer.finished || !lobbyState.gameStarted) return;

                // Generate a fake word (could be random or from a predefined list)
                const fakeWords = [
                    'etymology', 'language', 'word', 'definition', 'meaning',
                    'noun', 'verb', 'adjective', 'latin', 'greek',
                    'english', 'french', 'german', 'spanish', 'italian',
                    'root', 'prefix', 'suffix', 'plural', 'singular',
                    'synonym', 'antonym', 'homonym', 'translation', 'origin'
                ];

                // Small chance to "find" the target
                const shouldFinish = Math.random() < 0.08 && fakePlayer.clickCount >= 3;

                if (shouldFinish) {
                    fakePlayer.currentWord = lobbyState.targetWord;
                    fakePlayer.path.push(lobbyState.targetWord);
                    fakePlayer.clickCount++;
                    fakePlayer.finished = true;
                    fakePlayer.finishTime = Math.floor((Date.now() - gameStartTime) / 1000);
                    notifyStateChange();

                    // Clear interval
                    if (fakePlayerIntervals.has(fakePlayer.id)) {
                        clearInterval(fakePlayerIntervals.get(fakePlayer.id));
                        fakePlayerIntervals.delete(fakePlayer.id);
                    }
                } else {
                    const randomWord = fakeWords[Math.floor(Math.random() * fakeWords.length)];
                    fakePlayer.currentWord = randomWord;
                    fakePlayer.path.push(randomWord);
                    fakePlayer.clickCount++;
                    notifyStateChange();

                    // Schedule next move
                    const nextDelay = 2000 + Math.random() * 4000;
                    const intervalId = setTimeout(simulateMove, nextDelay);
                    fakePlayerIntervals.set(fakePlayer.id, intervalId);
                }
            };

            // Start first move after random delay
            const initialDelay = 1000 + Math.random() * 3000;
            const intervalId = setTimeout(simulateMove, initialDelay);
            fakePlayerIntervals.set(fakePlayer.id, intervalId);
        });
    }

    // Stop all fake player simulations
    function stopFakePlayerSimulation() {
        fakePlayerIntervals.forEach((intervalId) => {
            clearTimeout(intervalId);
        });
        fakePlayerIntervals.clear();
    }

    // Track game start time for fake player finish times
    let gameStartTime = null;

    // Override startGame to also start fake player simulation
    const originalStartGame = startGame;
    startGame = function() {
        originalStartGame();
        gameStartTime = Date.now();

        // Start fake player simulation after countdown
        setTimeout(() => {
            if (lobbyState.gameStarted && lobbyState.countdown === null) {
                startFakePlayerSimulation();
            }
        }, 4000); // Wait for 3 second countdown + 1 second buffer
    };

    // Override leave to also stop fake player simulation
    const originalLeave = leave;
    leave = function() {
        stopFakePlayerSimulation();
        originalLeave();
    };

    // Public API
    return {
        createRoom,
        joinRoom,
        acceptJoin,
        completeJoin,
        toggleReady,
        setChallengeWords,
        startGame,
        reportMove,
        reportFinish,
        leave,
        onStateChange,
        getState,
        // Debug functions
        addFakePlayer,
        stopFakePlayerSimulation
    };
})();
