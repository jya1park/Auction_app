import 'dart:math';

class TaxCalculator {
  static Map<String, dynamic> calculateAcquisitionTax({
    required int price,
    int housingCount = 1,
    bool isRegulatedArea = false,
    double areaSqm = 84.0,
    bool isResidential = true,
  }) {
    double taxRate;

    if (!isResidential) {
      taxRate = 0.04;
    } else if (housingCount >= 3) {
      taxRate = isRegulatedArea ? 0.12 : 0.08;
    } else if (housingCount == 2) {
      taxRate = isRegulatedArea ? 0.08 : _getBasicHousingRate(price);
    } else {
      taxRate = _getBasicHousingRate(price);
    }

    final acquisitionTax = (price * taxRate).round();
    final educationTax = (acquisitionTax * 0.10).round();
    final ruralTax =
        (isResidential && areaSqm > 85) ? (acquisitionTax * 0.20).round() : 0;

    int stampTax;
    if (price <= 100000000) {
      stampTax = 0;
    } else if (price <= 1000000000) {
      stampTax = 150000;
    } else {
      stampTax = 350000;
    }

    final total = acquisitionTax + educationTax + ruralTax + stampTax;

    return {
      'price': price,
      'housing_count': housingCount,
      'is_regulated_area': isRegulatedArea,
      'area_sqm': areaSqm,
      'is_residential': isResidential,
      'tax_rate': taxRate,
      'tax_rate_percent': '${(taxRate * 100).toStringAsFixed(1)}%',
      'acquisition_tax': acquisitionTax,
      'education_tax': educationTax,
      'rural_tax': ruralTax,
      'stamp_tax': stampTax,
      'total': total,
      'breakdown': '취득세: ${_won(acquisitionTax)} (${(taxRate * 100).toStringAsFixed(1)}%)\n'
          '지방교육세: ${_won(educationTax)} (취득세의 10%)\n'
          '농어촌특별세: ${ruralTax > 0 ? '${_won(ruralTax)} (취득세의 20%, 85㎡ 초과)' : '비과세 (85㎡ 이하)'}\n'
          '인지세: ${stampTax > 0 ? _won(stampTax) : '비과세 (1억 이하)'}\n'
          '──────────\n'
          '합계: ${_won(total)}',
    };
  }

  static double _getBasicHousingRate(int price) {
    if (price <= 600000000) return 0.01;
    if (price > 900000000) return 0.03;
    return (price / 100000000 * 2 / 3 - 3) / 100;
  }

  static Map<String, dynamic> calculateCapitalGainsTax({
    required int purchasePrice,
    required int salePrice,
    int holdingYears = 2,
    int housingCount = 1,
    bool isRegulatedArea = false,
    int acquisitionCosts = 0,
    int expenses = 0,
    bool isResident = true,
  }) {
    final totalAcquisition = purchasePrice + acquisitionCosts + expenses;
    final capitalGain = salePrice - totalAcquisition;

    if (capitalGain <= 0) {
      return {
        'purchase_price': purchasePrice,
        'sale_price': salePrice,
        'capital_gain': capitalGain,
        'tax': 0,
        'local_income_tax': 0,
        'total': 0,
        'breakdown': '양도차익: ${_won(capitalGain)}\n양도차익이 없으므로 양도소득세 없음',
      };
    }

    if (housingCount == 1 && holdingYears >= 2 && salePrice <= 1200000000) {
      final meetsResidency = !isRegulatedArea || isResident;
      if (meetsResidency) {
        return {
          'purchase_price': purchasePrice,
          'sale_price': salePrice,
          'capital_gain': capitalGain,
          'tax': 0,
          'local_income_tax': 0,
          'total': 0,
          'breakdown': '1세대 1주택 비과세 요건 충족\n'
              '- 보유기간: ${holdingYears}년 (2년 이상)\n'
              '- 양도가액: ${_won(salePrice)} (12억 이하)\n'
              '양도소득세: 0원',
        };
      }
    }

    int taxableGain = capitalGain;

    if (housingCount == 1 && holdingYears >= 2 && salePrice > 1200000000) {
      taxableGain =
          (capitalGain * (salePrice - 1200000000) / salePrice).round();
    }

    double ltcRate = 0;
    if (housingCount == 1 && isResident && holdingYears >= 3) {
      final holdDeduction = min(holdingYears, 10) * 4;
      ltcRate = holdDeduction / 100;
      if (isResident) {
        final resDeduction = min(holdingYears, 10) * 4;
        ltcRate = min((holdDeduction + resDeduction) / 100, 0.80);
      }
    } else if (housingCount <= 1 && holdingYears >= 3) {
      ltcRate = min(holdingYears * 2, 30) / 100;
    }

    final ltcDeduction = (taxableGain * ltcRate).round();
    final taxableIncome = taxableGain - ltcDeduction;

    final basicDeduction = 2500000;
    final taxBase = max(0, taxableIncome - basicDeduction);

    double rate;
    int progressiveDeduction;

    if (holdingYears < 1) {
      rate = housingCount >= 1 ? 0.70 : 0.50;
      progressiveDeduction = 0;
    } else if (holdingYears < 2) {
      rate = housingCount >= 1 ? 0.60 : 0.40;
      progressiveDeduction = 0;
    } else {
      final result = _getIncomeRate(taxBase);
      rate = result.$1;
      progressiveDeduction = result.$2;

      if (isRegulatedArea) {
        if (housingCount == 2) rate += 0.20;
        if (housingCount >= 3) rate += 0.30;
      }
    }

    final tax = max(0, (taxBase * rate).round() - progressiveDeduction);
    final localIncomeTax = (tax * 0.10).round();
    final total = tax + localIncomeTax;

    return {
      'purchase_price': purchasePrice,
      'sale_price': salePrice,
      'capital_gain': capitalGain,
      'taxable_gain': taxableGain,
      'ltc_rate': '${(ltcRate * 100).toStringAsFixed(0)}%',
      'ltc_deduction': ltcDeduction,
      'tax_base': taxBase,
      'tax_rate': '${(rate * 100).toStringAsFixed(0)}%',
      'tax': tax,
      'local_income_tax': localIncomeTax,
      'total': total,
      'breakdown': '양도가액: ${_won(salePrice)}\n'
          '취득가액: ${_won(totalAcquisition)}\n'
          '양도차익: ${_won(capitalGain)}\n'
          '${taxableGain != capitalGain ? '과세대상 양도차익: ${_won(taxableGain)}\n' : ''}'
          '장기보유특별공제(${(ltcRate * 100).toStringAsFixed(0)}%): -${_won(ltcDeduction)}\n'
          '기본공제: -${_won(basicDeduction)}\n'
          '과세표준: ${_won(taxBase)}\n'
          '세율: ${(rate * 100).toStringAsFixed(0)}%\n'
          '──────────\n'
          '양도소득세: ${_won(tax)}\n'
          '지방소득세(10%): ${_won(localIncomeTax)}\n'
          '합계: ${_won(total)}',
    };
  }

  static (double, int) _getIncomeRate(int taxBase) {
    if (taxBase <= 14000000) return (0.06, 0);
    if (taxBase <= 50000000) return (0.15, 1260000);
    if (taxBase <= 88000000) return (0.24, 5760000);
    if (taxBase <= 150000000) return (0.35, 15440000);
    if (taxBase <= 300000000) return (0.38, 19940000);
    if (taxBase <= 500000000) return (0.40, 25940000);
    if (taxBase <= 1000000000) return (0.42, 35940000);
    return (0.45, 65940000);
  }

  static Map<String, dynamic> calculateTotalCost({
    required int salePrice,
    int housingCount = 1,
    bool isRegulatedArea = false,
    double areaSqm = 84.0,
    bool isResidential = true,
    int lawyerFee = 500000,
    int movingCost = 3000000,
  }) {
    final taxResult = calculateAcquisitionTax(
      price: salePrice,
      housingCount: housingCount,
      isRegulatedArea: isRegulatedArea,
      areaSqm: areaSqm,
      isResidential: isResidential,
    );

    final totalTax = taxResult['total'] as int;
    final total = salePrice + totalTax + lawyerFee + movingCost;

    return {
      'sale_price': salePrice,
      'acquisition_tax_total': totalTax,
      'lawyer_fee': lawyerFee,
      'moving_cost': movingCost,
      'total': total,
      'breakdown': '낙찰대금: ${_won(salePrice)}\n'
          '──────────\n'
          '${taxResult['breakdown']}\n'
          '──────────\n'
          '법무사 비용 (예상): ${_won(lawyerFee)}\n'
          '명도비 (예상): ${_won(movingCost)}\n'
          '══════════\n'
          '총 예상 비용: ${_won(total)}',
    };
  }

  static String executeFunction(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'calculate_acquisition_tax':
        final result = calculateAcquisitionTax(
          price: args['price'] as int,
          housingCount: args['housing_count'] ?? 1,
          isRegulatedArea: args['is_regulated_area'] ?? false,
          areaSqm: (args['area_sqm'] ?? 84.0).toDouble(),
          isResidential: args['is_residential'] ?? true,
        );
        return json.encode(result);

      case 'calculate_capital_gains_tax':
        final result = calculateCapitalGainsTax(
          purchasePrice: args['purchase_price'] as int,
          salePrice: args['sale_price'] as int,
          holdingYears: args['holding_years'] ?? 2,
          housingCount: args['housing_count'] ?? 1,
          isRegulatedArea: args['is_regulated_area'] ?? false,
          acquisitionCosts: args['acquisition_costs'] ?? 0,
          expenses: args['expenses'] ?? 0,
        );
        return json.encode(result);

      case 'calculate_total_cost':
        final result = calculateTotalCost(
          salePrice: args['sale_price'] as int,
          housingCount: args['housing_count'] ?? 1,
          isRegulatedArea: args['is_regulated_area'] ?? false,
          areaSqm: (args['area_sqm'] ?? 84.0).toDouble(),
          isResidential: args['is_residential'] ?? true,
          lawyerFee: args['lawyer_fee'] ?? 500000,
          movingCost: args['moving_cost'] ?? 3000000,
        );
        return json.encode(result);

      default:
        return json.encode({'error': 'Unknown function: $name'});
    }
  }

  static String _won(int amount) {
    if (amount >= 100000000) {
      final eok = amount ~/ 100000000;
      final man = (amount % 100000000) ~/ 10000;
      if (man > 0) return '$eok억 ${_comma(man)}만원';
      return '$eok억원';
    }
    if (amount >= 10000) {
      return '${_comma(amount ~/ 10000)}만원';
    }
    return '${_comma(amount)}원';
  }

  static String _comma(int n) {
    return n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  static const toolDefinitions = [
    {
      'type': 'function',
      'function': {
        'name': 'calculate_acquisition_tax',
        'description':
            '부동산 취득세를 정확하게 계산합니다. 취득세, 지방교육세, 농어촌특별세, 인지세를 포함합니다. 세금 금액 계산이 필요할 때 반드시 이 함수를 사용하세요.',
        'parameters': {
          'type': 'object',
          'properties': {
            'price': {
              'type': 'integer',
              'description': '취득가액(낙찰가) 원 단위. 예: 5억 = 500000000',
            },
            'housing_count': {
              'type': 'integer',
              'description': '보유 주택 수 (이 물건 포함). 1주택=1, 2주택=2, 3주택이상=3',
              'default': 1,
            },
            'is_regulated_area': {
              'type': 'boolean',
              'description': '조정대상지역 여부',
              'default': false,
            },
            'area_sqm': {
              'type': 'number',
              'description': '전용면적 (㎡). 85㎡ 초과 시 농특세 부과',
              'default': 84.0,
            },
            'is_residential': {
              'type': 'boolean',
              'description': '주거용 여부. 상가/오피스텔(업무용)은 false',
              'default': true,
            },
          },
          'required': ['price'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'calculate_capital_gains_tax',
        'description':
            '양도소득세를 정확하게 계산합니다. 장기보유특별공제, 기본공제, 다주택 중과, 지방소득세를 포함합니다. 양도세 계산이 필요할 때 반드시 이 함수를 사용하세요.',
        'parameters': {
          'type': 'object',
          'properties': {
            'purchase_price': {
              'type': 'integer',
              'description': '취득가액(매입가/낙찰가) 원 단위',
            },
            'sale_price': {
              'type': 'integer',
              'description': '양도가액(매도가) 원 단위',
            },
            'holding_years': {
              'type': 'integer',
              'description': '보유기간 (년)',
              'default': 2,
            },
            'housing_count': {
              'type': 'integer',
              'description': '보유 주택 수',
              'default': 1,
            },
            'is_regulated_area': {
              'type': 'boolean',
              'description': '조정대상지역 여부',
              'default': false,
            },
            'acquisition_costs': {
              'type': 'integer',
              'description': '취득 부대비용 (취득세, 법무사비 등) 원 단위',
              'default': 0,
            },
            'expenses': {
              'type': 'integer',
              'description': '필요경비 (중개수수료, 수리비 등) 원 단위',
              'default': 0,
            },
          },
          'required': ['purchase_price', 'sale_price'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'calculate_total_cost',
        'description':
            '경매 낙찰 시 총 예상 비용을 계산합니다. 낙찰대금 + 취득세 + 법무사비 + 명도비를 합산합니다.',
        'parameters': {
          'type': 'object',
          'properties': {
            'sale_price': {
              'type': 'integer',
              'description': '낙찰가 원 단위',
            },
            'housing_count': {
              'type': 'integer',
              'description': '보유 주택 수',
              'default': 1,
            },
            'is_regulated_area': {
              'type': 'boolean',
              'description': '조정대상지역 여부',
              'default': false,
            },
            'area_sqm': {
              'type': 'number',
              'description': '전용면적 (㎡)',
              'default': 84.0,
            },
            'is_residential': {
              'type': 'boolean',
              'description': '주거용 여부',
              'default': true,
            },
            'lawyer_fee': {
              'type': 'integer',
              'description': '법무사 비용 (원)',
              'default': 500000,
            },
            'moving_cost': {
              'type': 'integer',
              'description': '예상 명도비용 (원)',
              'default': 3000000,
            },
          },
          'required': ['sale_price'],
        },
      },
    },
  ];
}
