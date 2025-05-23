// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.30;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() external view virtual override returns (string memory) {
        return _name;
    }

    function symbol() external view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() external view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() external view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _setOwner(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() external virtual onlyOwner {
        _setOwner(address(0));
    }

    function transferOwnership(address newOwner) external virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract MUGA is ERC20, Ownable {
    IUniswapV2Router02 public uniswapV2Router;
    address public immutable uniswapV2Pair;
    uint256 public payoutTaxAtAmount = 50000 * (10**18);
    uint256 public totalTax = 5;
    uint256 public launchBlock = 0;
    uint256 public launchTaxBlocks = 75;
    uint256 public launchTax = 70;
    uint256 public secondLaunchTax = 50;
    uint256 public thirdLaunchTax = 25;
    uint256 public maxTransactionAmount = 2000000 * (10**18);
    mapping (address => bool) public isTaxesExempt;
    mapping (address => bool) public isMaxTransactionExempt;
    address payable public constant taxWallet = payable(0);

    event PaidOutTaxes(uint256 contract_token_balance);
    event SetPayoutTaxAtAmount(uint256 _payoutTaxAtAmount);
    event SetTax(uint256 _tax);
    
    bool private inSwapping;
    modifier lockTheSwap {
        inSwapping = true;
        _;
        inSwapping = false;
    }

    constructor() ERC20("Make Utility Great Again", "MUGA") {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        isTaxesExempt[owner()] = true;
        isTaxesExempt[taxWallet] = true;
        isTaxesExempt[address(this)] = true;
        
        isMaxTransactionExempt[owner()] = true;
        isMaxTransactionExempt[taxWallet] = true;
        isMaxTransactionExempt[address(this)] = true;
        
        _mint(owner(), 100000000 * (10**18));
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "MUGA: transfer from the zero address");
        require(to != address(0), "MUGA: transfer to the zero address");

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if(from == uniswapV2Pair && !isMaxTransactionExempt[to]) {
            uint256 receiverBalance = balanceOf(to);
            uint256 newReceiverBalance = receiverBalance + amount;
            require(newReceiverBalance <= maxTransactionAmount, "MUGA: Exceeds max transaction amount");
        }
        
        uint256 contract_token_balance = balanceOf(address(this));
        bool overMinTokenBalance = contract_token_balance >= payoutTaxAtAmount;
       
        if(to == uniswapV2Pair && overMinTokenBalance && !inSwapping) {
            payoutTaxes(contract_token_balance);
        }

        if((to == uniswapV2Pair && !isTaxesExempt[from]) || (from == uniswapV2Pair && !isTaxesExempt[to])) {
            uint256 currentTaxRate = getCurrentTaxRate();
            uint256 taxes = (amount * currentTaxRate) / 100;
            amount -= taxes;
            super._transfer(from, address(this), taxes); 
        }

        super._transfer(from, to, amount);
    }

    function getCurrentTaxRate() public view returns (uint256) {
        uint256 blocksSinceLaunch = block.number - launchBlock;
        
        if (blocksSinceLaunch > launchTaxBlocks) {
            return totalTax;
        } else if (blocksSinceLaunch > 50) {
            return thirdLaunchTax;
        } else if (blocksSinceLaunch > 25) {
            return secondLaunchTax;
        } else {
            return launchTax;
        }
    }

    function payoutTaxes(uint256 contract_token_balance) private lockTheSwap {
        swapTokensForETH(contract_token_balance);
        taxWallet.transfer(address(this).balance);
        emit PaidOutTaxes(contract_token_balance);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        if(allowance(address(this), address(uniswapV2Router)) < tokenAmount) {
          _approve(address(this), address(uniswapV2Router), ~uint256(0));
        }

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function startLaunch() external onlyOwner {
        require(launchBlock == 0, "Launch already started");
        launchBlock = block.number;
    }

    function setTax(uint256 _tax) external onlyOwner {
        require(_tax <= 5, "Tax must be smaller than or equal to 5");
        totalTax = _tax;
        emit SetTax(_tax);
    }

    function setMaxTransactionAmount(uint256 newMaxTransactionAmount) external onlyOwner {
        require(newMaxTransactionAmount > 1000000 * (10**18), "Max transaction amount must be greater than 1,000,000");
        maxTransactionAmount = newMaxTransactionAmount;
    }

    function setTaxExemption(address account, bool status) external onlyOwner {
        isTaxesExempt[account] = status;
    }

    function setMaxTransactionExemption(address account, bool status) external onlyOwner {
        isMaxTransactionExempt[account] = status;
    }

    function setPayoutTaxAtAmount(uint256 _payoutTaxAtAmount) external onlyOwner {
        payoutTaxAtAmount = _payoutTaxAtAmount * (10**18);
        emit SetPayoutTaxAtAmount(_payoutTaxAtAmount);
    }

    receive() external payable {}

}
