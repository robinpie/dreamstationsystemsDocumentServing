// Game State
let gameState = {
    mode: null, // 'daily', 'practice', or 'multiplayer'
    startWord: null,
    targetWord: null,
    currentWord: null,
    path: [],
    clickCount: 0,
    startTime: null,
    timerInterval: null,
    elapsedTime: 0,
    date: null, // For daily challenges
    debugMode: false,
    isMultiplayer: false
};

// DOM Elements (initialized after DOM is ready)
let screens = {};
let elements = {};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    // Initialize DOM references
    screens = {
        home: document.getElementById('homeScreen'),
        practiceSetup: document.getElementById('practiceSetupScreen'),
        game: document.getElementById('gameScreen'),
        history: document.getElementById('historyScreen'),
        multiplayerSetup: document.getElementById('multiplayerSetupScreen'),
        multiplayerJoin: document.getElementById('multiplayerJoinScreen'),
        multiplayerLobby: document.getElementById('multiplayerLobbyScreen')
    };

    elements = {
        dailyChallengeBtn: document.getElementById('dailyChallengeBtn'),
        practiceModeBtn: document.getElementById('practiceModeBtn'),
        viewHistoryBtn: document.getElementById('viewHistoryBtn'),
        startPracticeBtn: document.getElementById('startPracticeBtn'),
        randomChallengeBtn: document.getElementById('randomChallengeBtn'),
        backFromPracticeBtn: document.getElementById('backFromPracticeBtn'),
        backFromHistoryBtn: document.getElementById('backFromHistoryBtn'),
        homeBtn: document.getElementById('homeBtn'),
        startWordInput: document.getElementById('startWord'),
        targetWordInput: document.getElementById('targetWord'),
        currentWordDisplay: document.getElementById('currentWord'),
        targetWordDisplay: document.getElementById('targetWordDisplay'),
        clickCountDisplay: document.getElementById('clickCount'),
        timerDisplay: document.getElementById('timer'),
        breadcrumbTrail: document.getElementById('breadcrumbTrail'),
        wiktionaryContent: document.getElementById('wiktionaryContent'),
        loadingIndicator: document.getElementById('loadingIndicator'),
        gameError: document.getElementById('gameError'),
        practiceError: document.getElementById('practiceError'),
        modeIndicator: document.getElementById('modeIndicator'),
        victoryModal: document.getElementById('victoryModal'),
        victoryClicks: document.getElementById('victoryClicks'),
        victoryTime: document.getElementById('victoryTime'),
        shareableText: document.getElementById('shareableText'),
        copyResultsBtn: document.getElementById('copyResultsBtn'),
        reviewPathBtn: document.getElementById('reviewPathBtn'),
        playAgainBtn: document.getElementById('playAgainBtn'),
        closeVictoryBtn: document.getElementById('closeVictoryBtn'),
        historyContent: document.getElementById('historyContent'),
        englishOnlyCheckbox: document.getElementById('englishOnlyCheckbox'),
        debugModeCheckbox: document.getElementById('debugModeCheckbox'),
        debugNavigation: document.getElementById('debugNavigation'),
        debugWordInput: document.getElementById('debugWordInput'),
        debugGoBtn: document.getElementById('debugGoBtn'),
        // Multiplayer elements
        multiplayerBtn: document.getElementById('multiplayerBtn'),
        playerNameInput: document.getElementById('playerName'),
        createRoomBtn: document.getElementById('createRoomBtn'),
        joinRoomBtn: document.getElementById('joinRoomBtn'),
        backFromMultiplayerBtn: document.getElementById('backFromMultiplayerBtn'),
        // Join screen
        hostRoomCode: document.getElementById('hostRoomCode'),
        generateJoinCodeBtn: document.getElementById('generateJoinCodeBtn'),
        joinStep1: document.getElementById('joinStep1'),
        joinStep2: document.getElementById('joinStep2'),
        joinStep3: document.getElementById('joinStep3'),
        myJoinCode: document.getElementById('myJoinCode'),
        copyJoinCodeBtn: document.getElementById('copyJoinCodeBtn'),
        acceptCode: document.getElementById('acceptCode'),
        completeJoinBtn: document.getElementById('completeJoinBtn'),
        joinError: document.getElementById('joinError'),
        backFromJoinBtn: document.getElementById('backFromJoinBtn'),
        // Lobby screen
        hostAddPlayer: document.getElementById('hostAddPlayer'),
        roomCode: document.getElementById('roomCode'),
        copyRoomCodeBtn: document.getElementById('copyRoomCodeBtn'),
        acceptPlayerSection: document.getElementById('acceptPlayerSection'),
        playerJoinCode: document.getElementById('playerJoinCode'),
        acceptPlayerBtn: document.getElementById('acceptPlayerBtn'),
        acceptCodeDisplay: document.getElementById('acceptCodeDisplay'),
        generatedAcceptCode: document.getElementById('generatedAcceptCode'),
        copyAcceptCodeBtn: document.getElementById('copyAcceptCodeBtn'),
        toggleAcceptSectionBtn: document.getElementById('toggleAcceptSectionBtn'),
        playerList: document.getElementById('playerList'),
        challengeSetup: document.getElementById('challengeSetup'),
        mpStartWord: document.getElementById('mpStartWord'),
        mpTargetWord: document.getElementById('mpTargetWord'),
        mpRandomChallengeBtn: document.getElementById('mpRandomChallengeBtn'),
        mpEnglishOnlyCheckbox: document.getElementById('mpEnglishOnlyCheckbox'),
        debugFakePlayers: document.getElementById('debugFakePlayers'),
        addFakePlayerBtn: document.getElementById('addFakePlayerBtn'),
        guestReadySection: document.getElementById('guestReadySection'),
        readyBtn: document.getElementById('readyBtn'),
        startGameSection: document.getElementById('startGameSection'),
        mpStartGameBtn: document.getElementById('mpStartGameBtn'),
        startGameStatus: document.getElementById('startGameStatus'),
        lobbyError: document.getElementById('lobbyError'),
        leaveLobbyBtn: document.getElementById('leaveLobbyBtn'),
        // Countdown
        countdownOverlay: document.getElementById('countdownOverlay'),
        countdownNumber: document.getElementById('countdownNumber'),
        // Opponents panel
        opponentsPanel: document.getElementById('opponentsPanel'),
        opponentsList: document.getElementById('opponentsList'),
        // MP Victory
        mpVictoryModal: document.getElementById('mpVictoryModal'),
        mpLeaderboard: document.getElementById('mpLeaderboard'),
        mpPlayAgainBtn: document.getElementById('mpPlayAgainBtn'),
        mpLeaveLobbyBtn: document.getElementById('mpLeaveLobbyBtn')
    };

    setupEventListeners();
});

function setupEventListeners() {
    elements.dailyChallengeBtn.addEventListener('click', startDailyChallenge);
    elements.practiceModeBtn.addEventListener('click', () => showScreen('practiceSetup'));
    elements.viewHistoryBtn.addEventListener('click', () => showScreen('history'));
    elements.startPracticeBtn.addEventListener('click', startPracticeMode);
    elements.randomChallengeBtn.addEventListener('click', getRandomChallenge);
    elements.backFromPracticeBtn.addEventListener('click', () => showScreen('home'));
    elements.backFromHistoryBtn.addEventListener('click', () => showScreen('home'));
    elements.homeBtn.addEventListener('click', () => {
        if (confirm('are you sure you want to leave? your progress will be lost.')) {
            if (gameState.isMultiplayer) {
                Multiplayer.leave();
                elements.opponentsPanel.classList.add('hidden');
            }
            resetGame();
            showScreen('home');
        }
    });
    elements.copyResultsBtn.addEventListener('click', copyResults);
    elements.reviewPathBtn.addEventListener('click', reviewPath);
    elements.playAgainBtn.addEventListener('click', () => {
        hideVictoryModal();
        showScreen('practiceSetup');
    });
    elements.closeVictoryBtn.addEventListener('click', hideVictoryModal);

    // Debug mode - restore from localStorage
    const savedDebugMode = localStorage.getItem('wiktionaryRacingDebugMode') === 'true';
    gameState.debugMode = savedDebugMode;
    elements.debugModeCheckbox.checked = savedDebugMode;

    elements.debugModeCheckbox.addEventListener('change', () => {
        gameState.debugMode = elements.debugModeCheckbox.checked;
        localStorage.setItem('wiktionaryRacingDebugMode', elements.debugModeCheckbox.checked);
    });
    elements.debugGoBtn.addEventListener('click', debugNavigate);
    elements.debugWordInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            debugNavigate();
        }
    });

    // Multiplayer event listeners
    elements.multiplayerBtn.addEventListener('click', () => showScreen('multiplayerSetup'));
    elements.backFromMultiplayerBtn.addEventListener('click', () => showScreen('home'));
    elements.createRoomBtn.addEventListener('click', handleCreateRoom);
    elements.joinRoomBtn.addEventListener('click', () => showScreen('multiplayerJoin'));
    elements.backFromJoinBtn.addEventListener('click', () => {
        resetJoinScreen();
        showScreen('multiplayerSetup');
    });

    // Join flow
    elements.generateJoinCodeBtn.addEventListener('click', handleGenerateJoinCode);
    elements.copyJoinCodeBtn.addEventListener('click', () => copyToClipboard(elements.myJoinCode, elements.copyJoinCodeBtn));
    elements.completeJoinBtn.addEventListener('click', handleCompleteJoin);

    // Lobby
    elements.copyRoomCodeBtn.addEventListener('click', () => copyToClipboard(elements.roomCode, elements.copyRoomCodeBtn));
    elements.toggleAcceptSectionBtn.addEventListener('click', toggleAcceptSection);
    elements.acceptPlayerBtn.addEventListener('click', handleAcceptPlayer);
    elements.copyAcceptCodeBtn.addEventListener('click', () => copyToClipboard(elements.generatedAcceptCode, elements.copyAcceptCodeBtn));
    elements.mpRandomChallengeBtn.addEventListener('click', handleMpRandomChallenge);
    elements.mpStartWord.addEventListener('input', handleChallengeWordsChange);
    elements.mpTargetWord.addEventListener('input', handleChallengeWordsChange);
    elements.addFakePlayerBtn.addEventListener('click', addFakePlayer);
    elements.readyBtn.addEventListener('click', handleReadyToggle);
    elements.mpStartGameBtn.addEventListener('click', handleStartMultiplayerGame);
    elements.leaveLobbyBtn.addEventListener('click', handleLeaveLobby);

    // MP Victory
    elements.mpPlayAgainBtn.addEventListener('click', handleMpPlayAgain);
    elements.mpLeaveLobbyBtn.addEventListener('click', handleMpLeaveFromVictory);

    // Set up multiplayer state change callback
    Multiplayer.onStateChange(handleMultiplayerStateChange);
}

// Screen Management
function showScreen(screenName) {
    Object.values(screens).forEach(screen => screen.classList.remove('active'));
    screens[screenName].classList.add('active');
    
    if (screenName === 'history') {
        loadHistory();
    }
}

// Daily Challenge
function startDailyChallenge() {
    const today = getCentralTimeDate();
    const challenge = dailyChallenges.find(c => c.date === today);
    
    if (!challenge) {
        alert('no challenge available for today. please try practice mode!');
        return;
    }
    
    // Check if already completed today
    const completed = getCompletedDailyChallenges();
    if (completed.some(c => c.date === today)) {
        if (!confirm('you\'ve already completed today\'s challenge. play again?')) {
            return;
        }
    }
    
    gameState.mode = 'daily';
    gameState.startWord = challenge.start;
    gameState.targetWord = challenge.target;
    gameState.date = today;
    
    startGame();
}

// Practice Mode
function startPracticeMode() {
    // Preserve user-entered capitalization for display,
    // but do comparisons in a case-insensitive way where needed.
    const startWord = elements.startWordInput.value.trim();
    const targetWord = elements.targetWordInput.value.trim();
    
    if (!startWord || !targetWord) {
        showError('practiceError', 'please enter both start and target words.');
        return;
    }
    
    // Treat words as the same if they only differ by case
    if (startWord.toLowerCase() === targetWord.toLowerCase()) {
        showError('practiceError', 'start and target words must be different.');
        return;
    }
    
    // Validate words exist
    elements.startPracticeBtn.disabled = true;
    elements.startPracticeBtn.textContent = 'validating...';
    
    Promise.all([
        validateWordExists(startWord),
        validateWordExists(targetWord)
    ]).then(([startExists, targetExists]) => {
        elements.startPracticeBtn.disabled = false;
        elements.startPracticeBtn.textContent = 'start';
        
        if (!startExists) {
            showError('practiceError', `"${startWord}" not found on wiktionary.`);
            return;
        }
        
        if (!targetExists) {
            showError('practiceError', `"${targetWord}" not found on wiktionary.`);
            return;
        }
        
        gameState.mode = 'practice';
        gameState.startWord = startWord;
        gameState.targetWord = targetWord;
        gameState.date = null;
        
        startGame();
    }).catch(error => {
        elements.startPracticeBtn.disabled = false;
        elements.startPracticeBtn.textContent = 'start';
        showError('practiceError', 'error validating words. please try again.');
        console.error('Validation error:', error);
    });
}

async function getRandomChallenge() {
    // Disable button and show loading state
    const btn = elements.randomChallengeBtn;
    const originalText = btn.textContent;
    btn.disabled = true;
    btn.textContent = 'loading...';
    hideError('practiceError');

    const englishOnly = elements.englishOnlyCheckbox.checked;

    try {
        let startWord = null;
        let targetWord = null;
        let attempts = 0;
        const maxAttempts = 10;

        // Keep trying until we get two different valid words
        while ((!startWord || !targetWord || startWord.toLowerCase() === targetWord.toLowerCase()) && attempts < maxAttempts) {
            attempts++;

            // Fetch two random words in parallel
            const [word1, word2] = await Promise.all([
                fetchRandomWord(0, 5, englishOnly),
                fetchRandomWord(0, 5, englishOnly)
            ]);
            
            if (word1 && word2 && word1.toLowerCase() !== word2.toLowerCase()) {
                startWord = word1;
                targetWord = word2;
                break;
            } else if (word1 && !startWord) {
                startWord = word1;
            } else if (word2 && !targetWord) {
                targetWord = word2;
            }
        }
        
        // If we got valid different words, use them
        if (startWord && targetWord && startWord.toLowerCase() !== targetWord.toLowerCase()) {
            elements.startWordInput.value = startWord;
            elements.targetWordInput.value = targetWord;
        } else {
            // Show error if we couldn't fetch valid random words
            showError('practiceError', 'failed to fetch random words from wiktionary. please try again.');
        }
    } catch (error) {
        console.error('Error fetching random words:', error);
        showError('practiceError', 'error fetching random words. please check your connection and try again.');
    } finally {
        btn.disabled = false;
        btn.textContent = originalText;
    }
}

async function fetchRandomWord(retryCount = 0, maxRetries = 5, englishOnly = true) {
    if (retryCount >= maxRetries) {
        console.warn('Max retries reached for random word fetch');
        return null;
    }
    
    try {
        // Use MediaWiki API to get a random page from main namespace (0 = articles)
        // We'll exclude namespaces like Category:, Template:, etc.
        const url = `https://en.wiktionary.org/w/api.php?action=query&list=random&rnnamespace=0&rnlimit=1&format=json&origin=*`;
        const response = await fetch(url);
        const data = await response.json();
        
        if (data.error) {
            throw new Error(data.error.info || 'API error');
        }
        
        const randomPages = data.query?.random || [];
        if (randomPages.length === 0) {
            throw new Error('No random pages returned');
        }
        
        const pageTitle = randomPages[0].title;
        
        // Filter out namespaces and special pages (but allow Appendix:)
        if (pageTitle.includes(':') && !pageTitle.startsWith('Appendix:')) {
            // If it's a namespace page, try again
            return await fetchRandomWord(retryCount + 1, maxRetries, englishOnly);
        }

        // Validate the word exists and is a real entry
        const exists = await validateWordExists(pageTitle);
        if (!exists) {
            // Try again if validation fails
            return await fetchRandomWord(retryCount + 1, maxRetries, englishOnly);
        }

        // Check if the word has an English section (if required)
        if (englishOnly) {
            const hasEnglish = await checkEnglishSection(pageTitle);
            if (!hasEnglish) {
                // If no English section, try again
                return await fetchRandomWord(retryCount + 1, maxRetries, englishOnly);
            }
        }
        
        return pageTitle;
    } catch (error) {
        console.error('Error fetching random word:', error);
        if (retryCount < maxRetries) {
            // Retry on error
            return await fetchRandomWord(retryCount + 1, maxRetries, englishOnly);
        }
        return null; // Return null to trigger fallback
    }
}

// Game Logic
function startGame() {
    resetGame();
    showScreen('game');

    gameState.currentWord = gameState.startWord;
    gameState.path = [gameState.startWord];
    gameState.startTime = Date.now();

    // Show/hide debug navigation
    elements.debugNavigation.style.display = gameState.debugMode ? 'flex' : 'none';

    updateUI();
    loadWiktionaryPage(gameState.startWord);
    startTimer();
}

function debugNavigate() {
    const word = elements.debugWordInput.value.trim();
    if (!word) return;

    gameState.currentWord = word;
    gameState.path.push(word);
    gameState.clickCount++;
    elements.debugWordInput.value = '';

    // Check for victory
    if (word.toLowerCase() === gameState.targetWord.toLowerCase()) {
        stopTimer();
        saveCompletion();
        showVictoryModal();
    } else {
        updateUI();
        loadWiktionaryPage(word);
    }
}

function resetGame() {
    gameState.currentWord = null;
    gameState.path = [];
    gameState.clickCount = 0;
    gameState.startTime = null;
    gameState.elapsedTime = 0;
    gameState.isMultiplayer = false;

    if (gameState.timerInterval) {
        clearInterval(gameState.timerInterval);
        gameState.timerInterval = null;
    }

    hideError('gameError');
    hideError('practiceError');
    elements.wiktionaryContent.innerHTML = '';
    elements.breadcrumbTrail.innerHTML = '';
    elements.opponentsPanel.classList.add('hidden');
    screens.game.classList.remove('multiplayer-active');
}

function updateUI() {
    elements.currentWordDisplay.textContent = gameState.currentWord || '-';
    elements.targetWordDisplay.textContent = gameState.targetWord || '-';
    elements.clickCountDisplay.textContent = gameState.clickCount;
    elements.modeIndicator.textContent = gameState.mode === 'daily' ? 'daily challenge' : 'practice mode';
    
    updateBreadcrumbTrail();
}

function updateBreadcrumbTrail() {
    if (gameState.path.length === 0) return;
    
    elements.breadcrumbTrail.innerHTML = '';
    gameState.path.forEach((word, index) => {
        const item = document.createElement('span');
        item.className = 'breadcrumb-item';
        
        const link = document.createElement('a');
        link.className = 'breadcrumb-link';
        link.textContent = word;
        link.href = '#';
        link.addEventListener('click', (e) => {
            e.preventDefault();
            if (index < gameState.path.length - 1) {
                // Navigate back to this word in path
                const newPath = gameState.path.slice(0, index + 1);
                gameState.path = newPath;
                gameState.currentWord = word;
                gameState.clickCount = index; // Adjust click count
                loadWiktionaryPage(word);
                updateUI();
            }
        });
        
        item.appendChild(link);
        
        if (index < gameState.path.length - 1) {
            const separator = document.createElement('span');
            separator.className = 'breadcrumb-separator';
            separator.textContent = '→';
            item.appendChild(separator);
        }
        
        elements.breadcrumbTrail.appendChild(item);
    });
}

// Wiktionary Integration
async function validateWordExists(word) {
    try {
        const url = `https://en.wiktionary.org/w/api.php?action=query&titles=${encodeURIComponent(word)}&format=json&origin=*`;
        const response = await fetch(url);
        const data = await response.json();
        
        const pages = data.query?.pages || {};
        const pageId = Object.keys(pages)[0];
        return pageId !== '-1' && pages[pageId].missing === undefined;
    } catch (error) {
        console.error('Validation error:', error);
        return false;
    }
}

async function checkEnglishSection(word) {
    try {
        // Use the parse API to get the page content and check for English section
        const url = `https://en.wiktionary.org/w/api.php?action=parse&page=${encodeURIComponent(word)}&prop=wikitext&format=json&origin=*`;
        const response = await fetch(url);
        const data = await response.json();
        
        if (data.error) {
            return false;
        }
        
        const wikitext = data.parse?.wikitext?.['*'] || '';
        
        // Check for English language section markers
        // Wiktionary uses "==English==" or "== English ==" as section headers
        const englishPattern = /==\s*English\s*==/i;
        return englishPattern.test(wikitext);
    } catch (error) {
        console.error('Error checking English section:', error);
        // If we can't check, assume it's valid to avoid blocking valid words
        return true;
    }
}

async function loadWiktionaryPage(word) {
    elements.loadingIndicator.style.display = 'block';
    elements.wiktionaryContent.style.display = 'none';
    hideError('gameError');
    
    try {
        // Use MediaWiki API to get page content
        const apiUrl = `https://en.wiktionary.org/w/api.php?action=parse&page=${encodeURIComponent(word)}&format=json&prop=text&origin=*`;
        const response = await fetch(apiUrl);
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const data = await response.json();
        
        if (data.error) {
            throw new Error(data.error.info || 'Page not found');
        }
        
        const html = data.parse.text['*'];
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        
        // Get main content area
        const content = doc.querySelector('.mw-parser-output') || doc.body;
        
        // Remove unwanted elements
        const elementsToRemove = [
            '.mw-jump-link',
            '.mw-editsection',
            '.mw-editsection-like',
            '.navbox',
            '.infobox',
            '.hatnote',
            '.dablink',
            '.reference',
            '.mw-cite-backlink',
            '.catlinks',
            '.printfooter',
            '.mw-indicators',
            'script',
            'style'
        ];
        
        elementsToRemove.forEach(selector => {
            content.querySelectorAll(selector).forEach(el => el.remove());
        });

        // Remove empty list items (Wiktionary sometimes has empty li elements from templates)
        content.querySelectorAll('li').forEach(li => {
            // Check if the li only contains whitespace or empty elements
            const textContent = li.textContent.trim();
            const hasVisibleChildren = li.querySelector('a, img, table');
            if (!textContent && !hasVisibleChildren) {
                li.remove();
            }
        });
        
        // Insert content into DOM first
        elements.wiktionaryContent.innerHTML = content.innerHTML;
        elements.loadingIndicator.style.display = 'none';
        elements.wiktionaryContent.style.display = 'block';
        
        // Fix image URLs - convert relative paths to absolute URLs
        const images = elements.wiktionaryContent.querySelectorAll('img');
        images.forEach(img => {
            // Fix src attribute
            const src = img.getAttribute('src');
            if (src && !src.startsWith('http://') && !src.startsWith('https://') && !src.startsWith('data:')) {
                if (src.startsWith('//')) {
                    img.src = 'https:' + src;
                } else if (src.startsWith('/')) {
                    img.src = 'https://en.wiktionary.org' + src;
                } else {
                    img.src = 'https://en.wiktionary.org/' + src;
                }
            }
            
            // Fix data-src (lazy loading)
            const dataSrc = img.getAttribute('data-src');
            if (dataSrc && !dataSrc.startsWith('http://') && !dataSrc.startsWith('https://') && !dataSrc.startsWith('data:')) {
                let absoluteUrl;
                if (dataSrc.startsWith('//')) {
                    absoluteUrl = 'https:' + dataSrc;
                } else if (dataSrc.startsWith('/')) {
                    absoluteUrl = 'https://en.wiktionary.org' + dataSrc;
                } else {
                    absoluteUrl = 'https://en.wiktionary.org/' + dataSrc;
                }
                img.setAttribute('data-src', absoluteUrl);
            }
            
            // Fix srcset attribute
            const srcset = img.getAttribute('srcset');
            if (srcset) {
                const srcsetParts = srcset.split(',').map(part => {
                    const trimmed = part.trim();
                    const parts = trimmed.split(/\s+/);
                    const url = parts[0];
                    const descriptor = parts.slice(1).join(' ');
                    
                    if (url && !url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('data:')) {
                        let absoluteUrl;
                        if (url.startsWith('//')) {
                            absoluteUrl = 'https:' + url;
                        } else if (url.startsWith('/')) {
                            absoluteUrl = 'https://en.wiktionary.org' + url;
                        } else {
                            absoluteUrl = 'https://en.wiktionary.org/' + url;
                        }
                        return descriptor ? `${absoluteUrl} ${descriptor}` : absoluteUrl;
                    }
                    return trimmed;
                });
                img.setAttribute('srcset', srcsetParts.join(', '));
            }
        });
        
        // Fix source elements in picture elements
        const sources = elements.wiktionaryContent.querySelectorAll('picture source[srcset]');
        sources.forEach(source => {
            const srcset = source.getAttribute('srcset');
            if (srcset) {
                const srcsetParts = srcset.split(',').map(part => {
                    const trimmed = part.trim();
                    const parts = trimmed.split(/\s+/);
                    const url = parts[0];
                    const descriptor = parts.slice(1).join(' ');
                    
                    if (url && !url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('data:')) {
                        let absoluteUrl;
                        if (url.startsWith('//')) {
                            absoluteUrl = 'https:' + url;
                        } else if (url.startsWith('/')) {
                            absoluteUrl = 'https://en.wiktionary.org' + url;
                        } else {
                            absoluteUrl = 'https://en.wiktionary.org/' + url;
                        }
                        return descriptor ? `${absoluteUrl} ${descriptor}` : absoluteUrl;
                    }
                    return trimmed;
                });
                source.setAttribute('srcset', srcsetParts.join(', '));
            }
        });
        
        // Now process links in the actual DOM (after insertion)
        const links = elements.wiktionaryContent.querySelectorAll('a[href]');
        links.forEach(link => {
            const href = link.getAttribute('href');
            const linkClass = link.getAttribute('class') || '';
            const linkTitle = link.getAttribute('title') || '';
            
            if (!href) return;
            
            // Check for external link indicators in class
            const isExternal = linkClass.includes('extiw') || 
                              linkClass.includes('external') ||
                              linkClass.includes('external-autonumber') ||
                              linkClass.includes('external-free');
            
            // Check for Wikipedia links
            const isWikipedia = href.includes('wikipedia.org') ||
                               linkTitle.includes('wikipedia.org') ||
                               linkTitle.toLowerCase().includes('wikipedia');
            
            // Handle absolute URLs
            if (href.startsWith('http://') || href.startsWith('https://')) {
                // Allow absolute URLs to en.wiktionary.org (including all namespaces)
                if (href.includes('en.wiktionary.org/wiki/') || href.includes('en.wiktionary.org/w/')) {
                    const wordMatch = href.match(/en\.wiktionary\.org\/(?:wiki|w)\/(.+?)(?:#|\?|$)/);
                    if (wordMatch) {
                        const linkedWord = decodeURIComponent(wordMatch[1]).replace(/_/g, ' ');
                        
                        link.addEventListener('click', (e) => {
                            e.preventDefault();
                            handleLinkClick(linkedWord);
                        });
                        link.style.cursor = 'pointer';
                        return;
                    }
                }
                
                // Block all other external URLs (including Wikipedia)
                link.style.opacity = '0.5';
                link.style.pointerEvents = 'none';
                link.title = isWikipedia ? 'Wikipedia links are not allowed' : 'External links are not allowed';
                return;
            }
            
            // Block Wikipedia links detected by other means
            if (isWikipedia || isExternal) {
                link.style.opacity = '0.5';
                link.style.pointerEvents = 'none';
                link.title = 'Wikipedia and external links are not allowed';
                return;
            }
            
            // Process relative internal Wiktionary links (including all namespaces)
            if (href.startsWith('/wiki/') || href.startsWith('/w/')) {
                const wordMatch = href.match(/\/(?:wiki|w)\/(.+?)(?:#|$)/);
                if (wordMatch) {
                    const linkedWord = decodeURIComponent(wordMatch[1]).replace(/_/g, ' ');
                    
                    link.addEventListener('click', (e) => {
                        e.preventDefault();
                        handleLinkClick(linkedWord);
                    });
                    link.style.cursor = 'pointer';
                }
            } else if (href.startsWith('#')) {
                // Anchor links (same page) - allow but don't intercept
                // These are fine for navigation within the page
            } else {
                // Any other relative link - disable it
                link.style.opacity = '0.5';
                link.style.pointerEvents = 'none';
                link.title = 'Only internal Wiktionary links are allowed';
            }
        });
        
        // Scroll to top
        window.scrollTo(0, 0);
        
    } catch (error) {
        console.error('Error loading page:', error);
        elements.loadingIndicator.style.display = 'none';
        showError('gameError', `error loading page: ${error.message}. please try again.`);
    }
}

function handleLinkClick(word) {
    // Normalize word (remove section anchors, etc.)
    const normalizedWord = word.split('#')[0].trim();

    if (normalizedWord.toLowerCase() === gameState.targetWord.toLowerCase()) {
        // Victory!
        gameState.path.push(normalizedWord);
        gameState.clickCount++;
        stopTimer();

        if (gameState.isMultiplayer) {
            // Report finish to other players
            Multiplayer.reportFinish(gameState.elapsedTime, gameState.clickCount, gameState.path);
            // Check if all players finished (handled in state change callback)
        } else {
            saveCompletion();
            showVictoryModal();
        }
    } else {
        // Continue navigating
        gameState.currentWord = normalizedWord;
        gameState.path.push(normalizedWord);
        gameState.clickCount++;

        // Report move to other players in multiplayer
        if (gameState.isMultiplayer) {
            Multiplayer.reportMove(normalizedWord, [...gameState.path], gameState.clickCount);
        }

        updateUI();
        loadWiktionaryPage(normalizedWord);
    }
}

// Timer
function startTimer() {
    gameState.startTime = Date.now();
    gameState.timerInterval = setInterval(() => {
        if (gameState.startTime) {
            gameState.elapsedTime = Math.floor((Date.now() - gameState.startTime) / 1000);
            updateTimerDisplay();
        }
    }, 100);
}

function stopTimer() {
    if (gameState.timerInterval) {
        clearInterval(gameState.timerInterval);
        gameState.timerInterval = null;
    }
    if (gameState.startTime) {
        gameState.elapsedTime = Math.floor((Date.now() - gameState.startTime) / 1000);
    }
}

function updateTimerDisplay() {
    const minutes = Math.floor(gameState.elapsedTime / 60);
    const seconds = gameState.elapsedTime % 60;
    elements.timerDisplay.textContent = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

function formatTime(seconds) {
    const minutes = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

// Victory Modal
function showVictoryModal() {
    elements.victoryClicks.textContent = gameState.clickCount;
    elements.victoryTime.textContent = formatTime(gameState.elapsedTime);
    
    // Generate shareable text
    const dateStr = gameState.mode === 'daily' 
        ? gameState.date 
        : 'practice';
    const pathStr = gameState.path.join(' → ');
    
    const shareable = `wiktionary racing ${dateStr}
${gameState.startWord} → ${gameState.targetWord}
clicks: ${gameState.clickCount} | time: ${formatTime(gameState.elapsedTime)}

path:
${pathStr}

https://robinpie.neocities.org/wiktionaryRacingV2/wiktionaryRacingV2`;
    
    elements.shareableText.value = shareable;
    elements.victoryModal.classList.add('active');
}

function hideVictoryModal() {
    elements.victoryModal.classList.remove('active');
}

function copyResults() {
    elements.shareableText.select();
    document.execCommand('copy');
    elements.copyResultsBtn.textContent = 'copied!';
    setTimeout(() => {
        elements.copyResultsBtn.textContent = 'copy results';
    }, 2000);
}

function reviewPath() {
    hideVictoryModal();
    // Show the path in breadcrumb - already visible
    // Could scroll to breadcrumb or highlight it
    elements.breadcrumbTrail.scrollIntoView({ behavior: 'smooth' });
}

// History
function saveCompletion() {
    // Don't save history in debug mode
    if (gameState.debugMode) return;

    const completion = {
        mode: gameState.mode,
        date: gameState.date || new Date().toISOString().split('T')[0],
        startWord: gameState.startWord,
        targetWord: gameState.targetWord,
        clickCount: gameState.clickCount,
        time: gameState.elapsedTime,
        path: [...gameState.path],
        timestamp: Date.now()
    };
    
    let history = JSON.parse(localStorage.getItem('wiktionaryRacingHistory') || '[]');
    history.unshift(completion);
    
    // Keep only last 100 entries
    if (history.length > 100) {
        history = history.slice(0, 100);
    }
    
    localStorage.setItem('wiktionaryRacingHistory', JSON.stringify(history));
}

function loadHistory() {
    const history = JSON.parse(localStorage.getItem('wiktionaryRacingHistory') || '[]');
    
    if (history.length === 0) {
        elements.historyContent.innerHTML = '<div class="history-empty">no history yet. complete a challenge to see it here!</div>';
        return;
    }
    
    elements.historyContent.innerHTML = history.map(item => {
        const dateStr = item.mode === 'daily' 
            ? `daily challenge - ${item.date}`
            : `practice mode - ${new Date(item.timestamp).toLocaleDateString()}`;
        
        const pathStr = item.path.join(' → ');
        
        return `
            <div class="history-item">
                <div class="history-item-header">
                    <div class="history-item-title">${item.startWord} → ${item.targetWord}</div>
                    <div class="history-item-date">${dateStr}</div>
                </div>
                <div class="history-item-stats">
                    <span>clicks: ${item.clickCount}</span>
                    <span>time: ${formatTime(item.time)}</span>
                </div>
                <div class="history-item-path">path: ${pathStr}</div>
            </div>
        `;
    }).join('');
}

// Date Utilities
function getCentralTimeDate() {
    // Get current date in Central Time
    const now = new Date();
    const centralTime = new Date(now.toLocaleString('en-US', { timeZone: 'America/Chicago' }));
    const year = centralTime.getFullYear();
    const month = String(centralTime.getMonth() + 1).padStart(2, '0');
    const day = String(centralTime.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function getCompletedDailyChallenges() {
    const history = JSON.parse(localStorage.getItem('wiktionaryRacingHistory') || '[]');
    return history.filter(item => item.mode === 'daily');
}

// Error Handling
function showError(elementId, message) {
    const errorElement = elements[elementId];
    if (errorElement) {
        errorElement.textContent = message;
        errorElement.classList.add('show');
    }
}

function hideError(elementId) {
    const errorElement = elements[elementId];
    if (errorElement) {
        errorElement.classList.remove('show');
    }
}

// ==================== MULTIPLAYER FUNCTIONS ====================

// Utility: Copy text to clipboard
function copyToClipboard(textareaElement, buttonElement) {
    textareaElement.select();
    document.execCommand('copy');
    const originalText = buttonElement.textContent;
    buttonElement.textContent = 'copied!';
    setTimeout(() => {
        buttonElement.textContent = originalText;
    }, 2000);
}

// Create Room (Host)
async function handleCreateRoom() {
    const playerName = elements.playerNameInput.value.trim() || 'Host';
    elements.createRoomBtn.disabled = true;
    elements.createRoomBtn.textContent = 'creating...';

    try {
        const roomCode = await Multiplayer.createRoom(playerName);
        elements.roomCode.value = roomCode;
        showScreen('multiplayerLobby');
        updateLobbyUI();
    } catch (error) {
        console.error('Error creating room:', error);
        alert('Failed to create room. Please try again.');
    } finally {
        elements.createRoomBtn.disabled = false;
        elements.createRoomBtn.textContent = 'create room';
    }
}

// Join Flow - Step 1: Generate join code
async function handleGenerateJoinCode() {
    const hostCode = elements.hostRoomCode.value.trim();
    const playerName = elements.playerNameInput.value.trim() || 'Guest';

    if (!hostCode) {
        showError('joinError', 'please paste the room code from the host.');
        return;
    }

    hideError('joinError');
    elements.generateJoinCodeBtn.disabled = true;
    elements.generateJoinCodeBtn.textContent = 'generating...';

    try {
        const joinCode = await Multiplayer.joinRoom(hostCode, playerName);
        elements.myJoinCode.value = joinCode;
        elements.joinStep1.classList.add('hidden');
        elements.joinStep2.classList.remove('hidden');
        elements.joinStep3.classList.remove('hidden');
    } catch (error) {
        console.error('Error generating join code:', error);
        showError('joinError', 'invalid room code. please check and try again.');
    } finally {
        elements.generateJoinCodeBtn.disabled = false;
        elements.generateJoinCodeBtn.textContent = 'generate join code';
    }
}

// Join Flow - Step 3: Complete join
async function handleCompleteJoin() {
    const acceptCode = elements.acceptCode.value.trim();

    if (!acceptCode) {
        showError('joinError', 'please paste the accept code from the host.');
        return;
    }

    hideError('joinError');
    elements.completeJoinBtn.disabled = true;
    elements.completeJoinBtn.textContent = 'joining...';

    try {
        await Multiplayer.completeJoin(acceptCode);
        showScreen('multiplayerLobby');
        updateLobbyUI();
    } catch (error) {
        console.error('Error completing join:', error);
        showError('joinError', 'invalid accept code. please check and try again.');
    } finally {
        elements.completeJoinBtn.disabled = false;
        elements.completeJoinBtn.textContent = 'join lobby';
    }
}

// Reset join screen
function resetJoinScreen() {
    elements.hostRoomCode.value = '';
    elements.myJoinCode.value = '';
    elements.acceptCode.value = '';
    elements.joinStep1.classList.remove('hidden');
    elements.joinStep2.classList.add('hidden');
    elements.joinStep3.classList.add('hidden');
    hideError('joinError');
}

// Toggle accept player section
function toggleAcceptSection() {
    const section = elements.acceptPlayerSection;
    section.classList.toggle('hidden');
    elements.toggleAcceptSectionBtn.textContent = section.classList.contains('hidden')
        ? 'add a player'
        : 'hide';
}

// Host: Accept a player
async function handleAcceptPlayer() {
    const joinCode = elements.playerJoinCode.value.trim();

    if (!joinCode) {
        showError('lobbyError', 'please paste the player\'s join code.');
        return;
    }

    hideError('lobbyError');
    elements.acceptPlayerBtn.disabled = true;
    elements.acceptPlayerBtn.textContent = 'accepting...';

    try {
        const acceptCode = await Multiplayer.acceptJoin(joinCode);
        elements.generatedAcceptCode.value = acceptCode;
        elements.acceptCodeDisplay.classList.remove('hidden');
        elements.playerJoinCode.value = '';
    } catch (error) {
        console.error('Error accepting player:', error);
        showError('lobbyError', 'invalid join code. please check and try again.');
    } finally {
        elements.acceptPlayerBtn.disabled = false;
        elements.acceptPlayerBtn.textContent = 'accept player';
    }
}

// Handle random challenge for multiplayer
async function handleMpRandomChallenge() {
    const btn = elements.mpRandomChallengeBtn;
    btn.disabled = true;
    btn.textContent = 'loading...';

    const englishOnly = elements.mpEnglishOnlyCheckbox.checked;

    try {
        const [word1, word2] = await Promise.all([
            fetchRandomWord(0, 5, englishOnly),
            fetchRandomWord(0, 5, englishOnly)
        ]);

        if (word1 && word2 && word1.toLowerCase() !== word2.toLowerCase()) {
            elements.mpStartWord.value = word1;
            elements.mpTargetWord.value = word2;
            Multiplayer.setChallengeWords(word1, word2);
        } else {
            showError('lobbyError', 'failed to fetch random words. please try again.');
        }
    } catch (error) {
        console.error('Error fetching random words:', error);
        showError('lobbyError', 'error fetching random words.');
    } finally {
        btn.disabled = false;
        btn.textContent = 'random challenge';
    }
}

// Handle challenge words change
function handleChallengeWordsChange() {
    const startWord = elements.mpStartWord.value.trim();
    const targetWord = elements.mpTargetWord.value.trim();
    Multiplayer.setChallengeWords(startWord, targetWord);
}

// Toggle ready state
function handleReadyToggle() {
    Multiplayer.toggleReady();
}

// Add fake player (debug mode only)
function addFakePlayer() {
    Multiplayer.addFakePlayer();
}

// Start multiplayer game (host only)
function handleStartMultiplayerGame() {
    Multiplayer.startGame();
}

// Leave lobby
function handleLeaveLobby() {
    if (confirm('are you sure you want to leave the lobby?')) {
        Multiplayer.leave();
        showScreen('home');
    }
}

// Handle play again from MP victory
function handleMpPlayAgain() {
    elements.mpVictoryModal.classList.remove('active');
    showScreen('multiplayerLobby');
    updateLobbyUI();
}

// Handle leave from MP victory
function handleMpLeaveFromVictory() {
    elements.mpVictoryModal.classList.remove('active');
    Multiplayer.leave();
    showScreen('home');
}

// Handle multiplayer state changes
function handleMultiplayerStateChange(state) {
    updateLobbyUI();

    // Handle countdown
    if (state.lobbyState.countdown !== null && state.lobbyState.gameStarted) {
        elements.countdownOverlay.classList.remove('hidden');
        elements.countdownNumber.textContent = state.lobbyState.countdown > 0 ? state.lobbyState.countdown : 'GO!';
    } else if (state.lobbyState.countdown === null && state.lobbyState.gameStarted) {
        elements.countdownOverlay.classList.add('hidden');

        // Start the game if countdown just ended
        if (!gameState.isMultiplayer) {
            startMultiplayerGame(state.lobbyState);
        }
    }

    // Update opponents panel during game
    if (gameState.isMultiplayer && gameState.mode === 'multiplayer') {
        updateOpponentsPanel(state.lobbyState);
        checkMultiplayerVictory(state.lobbyState);
    }
}

// Update lobby UI
function updateLobbyUI() {
    const state = Multiplayer.getState();

    // Show/hide host controls
    if (state.isHost) {
        elements.hostAddPlayer.classList.remove('hidden');
        elements.challengeSetup.classList.remove('hidden');
        elements.guestReadySection.classList.add('hidden');
        elements.startGameSection.classList.remove('hidden');
        // Show debug fake players option if in debug mode
        if (gameState.debugMode) {
            elements.debugFakePlayers.classList.remove('hidden');
        } else {
            elements.debugFakePlayers.classList.add('hidden');
        }
    } else {
        elements.hostAddPlayer.classList.add('hidden');
        elements.challengeSetup.classList.add('hidden');
        elements.guestReadySection.classList.remove('hidden');
        elements.startGameSection.classList.add('hidden');
        elements.debugFakePlayers.classList.add('hidden');
    }

    // Update player list
    const players = state.lobbyState.players || [];
    elements.playerList.innerHTML = players.map(player => {
        let badge = '';
        if (player.isHost) {
            badge = '<span class="player-badge host">host</span>';
        } else if (player.isReady) {
            badge = '<span class="player-badge ready">ready</span>';
        } else {
            badge = '<span class="player-badge waiting">waiting</span>';
        }

        return `
            <div class="player-item">
                <div class="player-color" style="background-color: ${player.color}"></div>
                <span class="player-name">${escapeHtml(player.name)}</span>
                ${badge}
            </div>
        `;
    }).join('');

    // Update ready button text
    const localPlayer = players.find(p => p.id === state.localPeerId);
    if (localPlayer && !state.isHost) {
        elements.readyBtn.textContent = localPlayer.isReady ? 'not ready' : 'ready';
        elements.readyBtn.classList.toggle('btn-secondary', localPlayer.isReady);
        elements.readyBtn.classList.toggle('btn-primary', !localPlayer.isReady);
    }

    // Update start game button state (host only)
    if (state.isHost) {
        const allReady = players.every(p => p.isHost || p.isReady);
        const hasChallenge = state.lobbyState.startWord && state.lobbyState.targetWord;
        const hasPlayers = players.length >= 2;

        elements.mpStartGameBtn.disabled = !allReady || !hasChallenge || !hasPlayers;

        if (!hasPlayers) {
            elements.startGameStatus.textContent = 'waiting for players to join...';
        } else if (!hasChallenge) {
            elements.startGameStatus.textContent = 'set a challenge to start the game';
        } else if (!allReady) {
            elements.startGameStatus.textContent = 'waiting for all players to be ready...';
        } else {
            elements.startGameStatus.textContent = 'ready to start!';
        }

        // Show challenge info
        if (state.lobbyState.startWord && state.lobbyState.targetWord) {
            elements.mpStartWord.value = state.lobbyState.startWord;
            elements.mpTargetWord.value = state.lobbyState.targetWord;
        }
    }
}

// Start multiplayer game
function startMultiplayerGame(lobbyState) {
    gameState.mode = 'multiplayer';
    gameState.isMultiplayer = true;
    gameState.startWord = lobbyState.startWord;
    gameState.targetWord = lobbyState.targetWord;
    gameState.currentWord = lobbyState.startWord;
    gameState.path = [lobbyState.startWord];
    gameState.clickCount = 0;
    gameState.startTime = Date.now();
    gameState.elapsedTime = 0;

    // Show game screen
    showScreen('game');
    elements.opponentsPanel.classList.remove('hidden');
    screens.game.classList.add('multiplayer-active');
    elements.debugNavigation.style.display = 'none';

    updateUI();
    loadWiktionaryPage(gameState.startWord);
    startTimer();
}

// Update opponents panel during game
function updateOpponentsPanel(lobbyState) {
    const state = Multiplayer.getState();
    const opponents = lobbyState.players.filter(p => p.id !== state.localPeerId);

    elements.opponentsList.innerHTML = opponents.map(player => {
        const pathHtml = player.path && player.path.length > 0
            ? player.path.map((word, index) => {
                const isLast = index === player.path.length - 1;
                return `<span class="path-word ${isLast ? 'current' : ''}">${escapeHtml(word)}</span>`;
            }).join('<span class="path-arrow">→</span>')
            : '-';

        if (player.finished) {
            return `
                <div class="opponent-item finished" style="border-left-color: ${player.color}">
                    <div class="opponent-header">
                        <div class="opponent-color" style="background-color: ${player.color}"></div>
                        <span class="opponent-name">${escapeHtml(player.name)}</span>
                        <span class="opponent-finished-badge">finished!</span>
                    </div>
                    <div class="opponent-stats">${player.clickCount} clicks · ${formatTime(player.finishTime)}</div>
                    <div class="opponent-full-path">${pathHtml}</div>
                </div>
            `;
        }

        return `
            <div class="opponent-item" style="border-left-color: ${player.color}">
                <div class="opponent-header">
                    <div class="opponent-color" style="background-color: ${player.color}"></div>
                    <span class="opponent-name">${escapeHtml(player.name)}</span>
                    <span class="opponent-clicks">${player.clickCount} clicks</span>
                </div>
                <div class="opponent-full-path">${pathHtml}</div>
            </div>
        `;
    }).join('');
}

// Check if all players finished (for MP victory)
function checkMultiplayerVictory(lobbyState) {
    const allFinished = lobbyState.players.every(p => p.finished);

    if (allFinished && lobbyState.players.length > 0) {
        showMultiplayerVictory(lobbyState);
    }
}

// Show multiplayer victory modal
function showMultiplayerVictory(lobbyState) {
    // Sort players by finish time (DNF at the end)
    const sortedPlayers = [...lobbyState.players].sort((a, b) => {
        if (!a.finished && !b.finished) return 0;
        if (!a.finished) return 1;
        if (!b.finished) return -1;
        return a.finishTime - b.finishTime;
    });

    elements.mpLeaderboard.innerHTML = sortedPlayers.map((player, index) => {
        const rank = index + 1;
        const rankClass = rank === 1 ? 'first' : rank === 2 ? 'second' : rank === 3 ? 'third' : '';
        const isWinner = rank === 1;

        if (!player.finished) {
            return `
                <div class="leaderboard-item">
                    <div class="leaderboard-rank">${rank}</div>
                    <div class="leaderboard-player">
                        <div class="leaderboard-player-color" style="background-color: ${player.color}"></div>
                        <span class="leaderboard-player-name">${escapeHtml(player.name)}</span>
                    </div>
                    <div class="leaderboard-stats">
                        <span class="leaderboard-dnf">DNF</span>
                    </div>
                </div>
            `;
        }

        return `
            <div class="leaderboard-item ${isWinner ? 'winner' : ''}">
                <div class="leaderboard-rank ${rankClass}">${rank}</div>
                <div class="leaderboard-player">
                    <div class="leaderboard-player-color" style="background-color: ${player.color}"></div>
                    <span class="leaderboard-player-name">${escapeHtml(player.name)}</span>
                </div>
                <div class="leaderboard-stats">
                    <div class="leaderboard-clicks">${player.clickCount} clicks</div>
                    <div class="leaderboard-time">${formatTime(player.finishTime)}</div>
                </div>
            </div>
        `;
    }).join('');

    elements.mpVictoryModal.classList.add('active');
    stopTimer();
    elements.opponentsPanel.classList.add('hidden');
    gameState.isMultiplayer = false;
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

