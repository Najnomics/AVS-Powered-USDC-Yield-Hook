package main

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/Layr-Labs/hourglass-monorepo/ponos/pkg/performer/server"
	performerV1 "github.com/Layr-Labs/protocol-apis/gen/protos/eigenlayer/hourglass/v1/performer"
	"go.uber.org/zap"
)

// TaskType represents the different types of USDC Yield Intelligence tasks
type TaskType string

const (
	TaskTypeYieldMonitoring        TaskType = "yield_monitoring"
	TaskTypeCrossChainYieldCheck   TaskType = "cross_chain_yield_check"
	TaskTypeRebalanceExecution     TaskType = "rebalance_execution"
	TaskTypeRiskAssessment         TaskType = "risk_assessment"
)

// TaskPayload represents the structure of task payload data
type TaskPayload struct {
	Type       TaskType               `json:"type"`
	Parameters map[string]interface{} `json:"parameters"`
}

// parseTaskPayload extracts and parses the task payload from TaskRequest
func parseTaskPayload(t *performerV1.TaskRequest) (*TaskPayload, error) {
	var payload TaskPayload
	if err := json.Unmarshal(t.Payload, &payload); err != nil {
		return nil, fmt.Errorf("failed to parse task payload: %w", err)
	}
	return &payload, nil
}

// YieldIntelligencePerformer implements the Hourglass Performer interface for USDC Yield tasks.
// This offchain binary is run by Operators running the Hourglass Executor. It contains
// the business logic of the USDC Yield Intelligence AVS and performs work based on tasks sent to it.
//
// The Hourglass Aggregator ingests tasks from the TaskMailbox and distributes work
// to Executors configured to run the Yield Intelligence Performer. Performers execute the work and
// return the result to the Executor where the result is signed and returned to the
// Aggregator to place in the outbox once the signing threshold is met.
type YieldIntelligencePerformer struct {
	logger *zap.Logger
}

func NewYieldIntelligencePerformer(logger *zap.Logger) *YieldIntelligencePerformer {
	return &YieldIntelligencePerformer{
		logger: logger,
	}
}

func (yip *YieldIntelligencePerformer) ValidateTask(t *performerV1.TaskRequest) error {
	yip.logger.Sugar().Infow("Validating USDC Yield Intelligence task",
		zap.Any("task", t),
	)

	// ------------------------------------------------------------------------
	// USDC Yield Intelligence Task Validation Logic
	// ------------------------------------------------------------------------
	// Validate that the task request data is well-formed for yield optimization operations
	
	if len(t.TaskId) == 0 {
		return fmt.Errorf("task ID cannot be empty")
	}

	if len(t.Payload) == 0 {
		return fmt.Errorf("task payload cannot be empty")
	}

	// Parse and validate task payload
	payload, err := parseTaskPayload(t)
	if err != nil {
		return fmt.Errorf("failed to parse task payload: %w", err)
	}

	// Validate task type specific requirements
	switch payload.Type {
	case TaskTypeYieldMonitoring:
		if err := yip.validateYieldMonitoringTask(payload); err != nil {
			return fmt.Errorf("yield monitoring validation failed: %w", err)
		}
	case TaskTypeCrossChainYieldCheck:
		if err := yip.validateCrossChainYieldCheckTask(payload); err != nil {
			return fmt.Errorf("cross-chain yield check validation failed: %w", err)
		}
	case TaskTypeRebalanceExecution:
		if err := yip.validateRebalanceExecutionTask(payload); err != nil {
			return fmt.Errorf("rebalance execution validation failed: %w", err)
		}
	case TaskTypeRiskAssessment:
		if err := yip.validateRiskAssessmentTask(payload); err != nil {
			return fmt.Errorf("risk assessment validation failed: %w", err)
		}
	default:
		return fmt.Errorf("unknown task type: %s", payload.Type)
	}

	yip.logger.Sugar().Infow("Task validation successful", "taskId", string(t.TaskId))
	return nil
}

func (yip *YieldIntelligencePerformer) HandleTask(t *performerV1.TaskRequest) (*performerV1.TaskResponse, error) {
	yip.logger.Sugar().Infow("Handling USDC Yield Intelligence task",
		zap.Any("task", t),
	)

	// ------------------------------------------------------------------------
	// USDC Yield Intelligence Task Processing Logic
	// ------------------------------------------------------------------------
	// This is where the Performer will execute yield optimization work
	
	var resultBytes []byte
	var err error

	// Parse task payload to determine task type
	payload, err := parseTaskPayload(t)
	if err != nil {
		return nil, fmt.Errorf("failed to parse task payload: %w", err)
	}
	
	// Route to appropriate handler based on task type
	switch payload.Type {
	case TaskTypeYieldMonitoring:
		resultBytes, err = yip.handleYieldMonitoring(t, payload)
	case TaskTypeCrossChainYieldCheck:
		resultBytes, err = yip.handleCrossChainYieldCheck(t, payload)
	case TaskTypeRebalanceExecution:
		resultBytes, err = yip.handleRebalanceExecution(t, payload)
	case TaskTypeRiskAssessment:
		resultBytes, err = yip.handleRiskAssessment(t, payload)
	default:
		return nil, fmt.Errorf("unknown task type '%s' for task %s", payload.Type, string(t.TaskId))
	}

	if err != nil {
		yip.logger.Sugar().Errorw("Task processing failed", 
			"taskId", string(t.TaskId), 
			"error", err,
		)
		return nil, err
	}

	yip.logger.Sugar().Infow("Task processing completed successfully", 
		"taskId", string(t.TaskId),
		"resultSize", len(resultBytes),
	)

	return &performerV1.TaskResponse{
		TaskId: t.TaskId,
		Result: resultBytes,
	}, nil
}

// handleYieldMonitoring processes yield monitoring tasks
func (yip *YieldIntelligencePerformer) handleYieldMonitoring(t *performerV1.TaskRequest, payload *TaskPayload) ([]byte, error) {
	yip.logger.Sugar().Infow("Processing yield monitoring task", "taskId", string(t.TaskId))
	
	// TODO: Implement yield monitoring logic
	// Example parameter access:
	// protocol := payload.Parameters["protocol"].(string)
	// token := payload.Parameters["token"].(string)
	
	// - Fetch yield rates from lending protocols (Aave, Compound, Morpho)
	// - Calculate risk-adjusted yields
	// - Monitor for significant rate changes
	// - Submit yield data to Yield Intelligence Service Manager
	// - Return monitoring result
	
	return []byte("Yield monitoring completed"), nil
}

// handleCrossChainYieldCheck processes cross-chain yield comparison tasks
func (yip *YieldIntelligencePerformer) handleCrossChainYieldCheck(t *performerV1.TaskRequest, payload *TaskPayload) ([]byte, error) {
	yip.logger.Sugar().Infow("Processing cross-chain yield check task", "taskId", string(t.TaskId))
	
	// TODO: Implement cross-chain yield comparison logic
	// - Query yield rates across multiple chains (Ethereum, Base, Arbitrum)
	// - Factor in cross-chain transfer costs via CCTP
	// - Calculate net yield differences
	// - Identify profitable rebalancing opportunities
	// - Return cross-chain yield analysis
	
	return []byte("Cross-chain yield check completed"), nil
}

// handleRebalanceExecution processes USDC rebalancing execution tasks
func (yip *YieldIntelligencePerformer) handleRebalanceExecution(t *performerV1.TaskRequest, payload *TaskPayload) ([]byte, error) {
	yip.logger.Sugar().Infow("Processing rebalance execution task", "taskId", string(t.TaskId))
	
	// TODO: Implement rebalance execution logic
	// - Validate rebalancing opportunity from yield signals
	// - Calculate optimal allocation across protocols/chains
	// - Execute via Circle Wallets and CCTP v2
	// - Monitor execution success and gas costs
	// - Return execution result with performance metrics
	
	return []byte("Rebalance execution completed"), nil
}

// handleRiskAssessment processes protocol risk assessment tasks
func (yip *YieldIntelligencePerformer) handleRiskAssessment(t *performerV1.TaskRequest, payload *TaskPayload) ([]byte, error) {
	yip.logger.Sugar().Infow("Processing risk assessment task", "taskId", string(t.TaskId))
	
	// TODO: Implement risk assessment logic
	// - Analyze protocol TVL and utilization rates
	// - Check smart contract audit status
	// - Monitor governance and admin key risks
	// - Calculate risk-adjusted yield scores
	// - Return comprehensive risk assessment
	
	return []byte("Risk assessment completed"), nil
}

// USDC Yield Intelligence task validation functions
func (yip *YieldIntelligencePerformer) validateYieldMonitoringTask(payload *TaskPayload) error {
	// Validate required parameters for yield monitoring
	if protocol, ok := payload.Parameters["protocol"].(string); !ok || protocol == "" {
		return fmt.Errorf("missing or invalid protocol")
	}
	
	if token, ok := payload.Parameters["token"].(string); !ok || token != "USDC" {
		return fmt.Errorf("missing or invalid token, must be USDC")
	}
	
	if chainId, ok := payload.Parameters["chain_id"].(float64); !ok || chainId <= 0 {
		return fmt.Errorf("missing or invalid chain_id")
	}
	
	return nil
}

func (yip *YieldIntelligencePerformer) validateCrossChainYieldCheckTask(payload *TaskPayload) error {
	// Validate required parameters for cross-chain yield check
	if sourceChain, ok := payload.Parameters["source_chain"].(float64); !ok || sourceChain <= 0 {
		return fmt.Errorf("missing or invalid source_chain")
	}
	
	if targetChain, ok := payload.Parameters["target_chain"].(float64); !ok || targetChain <= 0 {
		return fmt.Errorf("missing or invalid target_chain")
	}
	
	if amount, ok := payload.Parameters["amount"].(float64); !ok || amount <= 0 {
		return fmt.Errorf("missing or invalid amount")
	}
	
	return nil
}

func (yip *YieldIntelligencePerformer) validateRebalanceExecutionTask(payload *TaskPayload) error {
	// Validate required parameters for rebalance execution
	if userAddress, ok := payload.Parameters["user_address"].(string); !ok || userAddress == "" {
		return fmt.Errorf("missing or invalid user_address")
	}
	
	if amount, ok := payload.Parameters["amount"].(float64); !ok || amount <= 0 {
		return fmt.Errorf("missing or invalid amount")
	}
	
	if targetProtocol, ok := payload.Parameters["target_protocol"].(string); !ok || targetProtocol == "" {
		return fmt.Errorf("missing or invalid target_protocol")
	}
	
	return nil
}

func (yip *YieldIntelligencePerformer) validateRiskAssessmentTask(payload *TaskPayload) error {
	// Validate required parameters for risk assessment
	if protocol, ok := payload.Parameters["protocol"].(string); !ok || protocol == "" {
		return fmt.Errorf("missing or invalid protocol")
	}
	
	if chainId, ok := payload.Parameters["chain_id"].(float64); !ok || chainId <= 0 {
		return fmt.Errorf("missing or invalid chain_id")
	}
	
	if assessmentType, ok := payload.Parameters["assessment_type"].(string); !ok || assessmentType == "" {
		return fmt.Errorf("missing or invalid assessment_type")
	}
	
	return nil
}

func main() {
	ctx := context.Background()
	l, _ := zap.NewProduction()

	performer := NewYieldIntelligencePerformer(l)

	pp, err := server.NewPonosPerformerWithRpcServer(&server.PonosPerformerConfig{
		Port:    8080,
		Timeout: 5 * time.Second,
	}, performer, l)
	if err != nil {
		panic(fmt.Errorf("failed to create USDC Yield Intelligence performer: %w", err))
	}

	l.Info("Starting USDC Yield Intelligence Performer on port 8080...")
	if err := pp.Start(ctx); err != nil {
		panic(err)
	}
}