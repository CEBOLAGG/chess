// Dependancies
const express = require('express');
const bodyParser = require('body-parser');

// Engine path
const enginePath = "stockfish.exe";

// Setup server
const app = express();

// Parse data into body
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Setup chess engine
const Engine = require('node-uci').Engine;
var engine = new Engine(enginePath);

async function setup() {
  engine = new Engine(enginePath);
  await engine.init();
  
  // Configurações otimizadas para AVALIAÇÃO RÁPIDA
  await engine.setoption('Hash', 512);        // Menos memória para ser mais rápido
  await engine.setoption('Threads', 4);       // Menos threads para avaliação rápida
  await engine.setoption('MultiPV', 1);
  await engine.setoption('Ponder', false);
  await engine.setoption('Contempt', 0);
  await engine.setoption('Move Overhead', 10); // Overhead mínimo
  
  await engine.isready();
}

// Extrai a última informação válida do array
function getLastInfo(infoArray) {
  if (!Array.isArray(infoArray)) return null;
  
  // Procura do fim para o início pela última entrada com dados completos
  for (let i = infoArray.length - 1; i >= 0; i--) {
    const info = infoArray[i];
    if (info.depth && info.score) {
      return info;
    }
  }
  
  return null;
}

(async () => {
  await setup();
  
  // Rota de AVALIAÇÃO RÁPIDA - Para eval bar em tempo real
  app.get('/api/evaluate', async (req, res) => {
    try {
      await engine.position(req.query.fen);
      
      // Análise RÁPIDA - apenas para eval bar
      const result = await engine.go({ 
        depth: 23,      // Depth baixo para velocidade
        movetime: 200   // 150ms - bem rápido
      });
      
      const lastInfo = getLastInfo(result.info);
      
      const response = {
        score: lastInfo?.score || { unit: 'cp', value: 0 },
        depth: lastInfo?.depth || null
      };
      
      res.json(response);
      
    } catch (error) {
      console.error('[EVAL ERROR]', error);
      await setup();
      res.status(500).json({ 
        error: "Failed to evaluate position",
        score: { unit: 'cp', value: 0 }
      });
    }
  });
  
  // Rota de status
  app.get('/api/status', (req, res) => {
    res.json({ 
      status: 'online', 
      engine: 'Stockfish Evaluation',
      config: {
        hash: '512 MB',
        threads: 4,
        depth: 12,
        movetime: '150ms',
        purpose: 'Fast evaluation for UI'
      }
    });
  });
  
  // Start listening
  app.listen(3001, () => {
    console.log('========================================');
    console.log('⚡ Stockfish EVAL Server');
    console.log('📡 Port: 3001');
    console.log('⚙️  Mode: Fast Evaluation');
    console.log('🎯 Depth: 12');
    console.log('⏱️  Time: 150ms');
    console.log('========================================');
  });
  
  // Graceful shutdown
  process.on('SIGINT', async () => {
    console.log('\n[SHUTDOWN] Closing Stockfish...');
    await engine.quit();
    process.exit(0);
  });
  
})();